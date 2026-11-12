import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/config/map_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/operations_service.dart';
import '../passenger/map/map_overlay.dart' show ApproximateRouteNote;
import '../passenger/map/passenger_map.dart';
import '../trip_tracking/models/trip_tracking.dart';
import '../trip_tracking/services/active_trip_tracking.dart';
import '../trip_tracking/services/trip_location_sender.dart';
import '../operations/services/next_stop_tracker.dart';

/// Shown when the Gateway answers 401.
const sessionExpiredMessage = 'Tu sesión expiró. Inicia sesión nuevamente.';

/// Completing answered 403 (not the driver's trip) or 404 (no such trip).
const cannotCompleteMessage = 'No puedes finalizar este viaje.';

/// Arguments of the `/driver/trip` route.
class TripScreenArgs {
  const TripScreenArgs({required this.trip, this.autoStart = false});

  final DriverTrip trip;
  final bool autoStart;
}

/// Driver screen for a trip (issue-4) with the real Dashboard trip.
///
/// It receives a trip the Dashboard already started (Home did the
/// `POST ops/trips/{id}/start`) and sends the bus GPS location every few
/// seconds ([TripLocationSender]). "Finalizar recorrido" stops the GPS and
/// completes the trip (`POST .../complete`).
///
/// **Map:** the route the driver must follow (the trip's planned line and
/// stops, `planned_route_snapshot`; else `GET ops/route-patterns/{id}`), the
/// bus position from the GPS and the **next stop**. Below it, a compact panel:
/// sending status, sent / pending, the "no cierres la app" notice and
/// "Finalizar recorrido".
///
/// The sender is the app-wide [ActiveTripTracking.sender]: leaving this tab
/// (Inicio, Mis rutas, Mi cuenta) does **not** stop the GPS, and coming back
/// shows it still sending.
///
/// Opened from the "Recorrido" tab without a trip, it looks for the driver's
/// trip that is already in progress (e.g. the app was closed mid-trip).
///
/// A 401 (loading, completing, or the GPS itself) clears the session and goes
/// to Login.
class TripScreen extends StatefulWidget {
  const TripScreen({
    super.key,
    this.trip,
    this.autoStart = false,
    this.operations,
    this.sender,
    this.sessionStore,
    this.mapBuilder = buildMapLibrePassengerMap,
  });

  /// The trip picked on the home tab; `null` = look for the one in progress.
  final DriverTrip? trip;

  /// When `true`, the GPS starts as soon as the screen opens (the driver
  /// started or continued the trip on the home tab).
  final bool autoStart;

  final OperationsService? operations;

  /// Defaults to the app-wide [ActiveTripTracking.sender]; tests plug in a
  /// fake (the real one needs the device GPS). Never disposed here.
  final TripLocationSender? sender;

  /// Cleared when the session expires (401).
  final SecureSessionStore? sessionStore;

  /// The map (MapLibre); tests plug in a fake.
  final PassengerMapBuilder mapBuilder;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  late final TripLocationSender _sender =
      widget.sender ?? ActiveTripTracking.sender;
  late final OperationsService _operations =
      widget.operations ?? OperationsService();
  late final SecureSessionStore _session =
      widget.sessionStore ?? SecureSessionStore();
  Timer? _ticker; // rebuilds every second so "hace Ns" stays fresh

  /// The session expired: already on the way to Login.
  bool _signingOut = false;

  DriverTrip? _trip;
  bool _loadingTrip = false;

  /// A call to the Dashboard (complete) is running.
  bool _busy = false;

  /// Last Dashboard error (complete or loading the trip).
  String? _tripError;

  /// Completing answered 403 / 404: the trip is not this driver's (or no
  /// longer exists). The GPS is stopped.
  bool _cannotComplete = false;

  // --- Map ---------------------------------------------------------------------

  PassengerMapHandle? _map;

  /// The route the driver must follow; `null` while unknown.
  RoutePattern? _route;
  NextStopTracker? _nextStop;

  /// The camera follows the bus (off after "Ver ruta completa").
  bool _follow = true;

  /// Last bus position drawn on the map.
  (double, double)? _drawnBus;

  static const _followZoom = 16.0;

  @override
  void initState() {
    super.initState();
    _sender.snapshot.addListener(_onSnapshot);
    // Back on the tab while the GPS kept sending: keep "hace Ns" fresh.
    _onSnapshot();
    _setTrip(widget.trip);
    if (_trip == null) {
      _loadActiveTrip();
    } else if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Only stop listening: the GPS keeps sending while the driver is on
    // another tab (ActiveTripTracking).
    _sender.snapshot.removeListener(_onSnapshot);
    super.dispose();
  }

  void _onSnapshot() {
    final snap = _sender.snapshot.value;
    if (snap.state == TripTrackingState.rejected && snap.sessionExpired) {
      // The GPS got 401: "Reintentar" would get 401 again.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onSessionExpired());
      return;
    }
    final tracking = snap.isTracking;
    if (tracking && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!tracking) {
      _ticker?.cancel();
      _ticker = null;
    }
    _onBusPosition(snap);
  }

  // --- Trip and route ----------------------------------------------------------

  /// Uses [trip] and its planned route. Asks the Dashboard for the current
  /// pattern when the trip carries no route, or carries stops without a line
  /// (planned before "Calculate Route" was done in the Dashboard).
  void _setTrip(DriverTrip? trip) {
    _trip = trip;
    final planned = trip?.plannedPattern;
    if (planned != null) {
      // Keep a line already taken from the current pattern.
      final line = _route?.hasGeometry ?? false ? _route!.geometry : null;
      _useRoute(
        !planned.hasGeometry && line != null
            ? planned.withGeometry(line)
            : planned,
      );
    }
    if (trip?.routePatternId case final String patternId
        when !(_route?.hasGeometry ?? false) &&
            !_routeFetched &&
            trip!.status == TripStatus.inProgress) {
      _routeFetched = true;
      unawaited(_fetchRoute(patternId));
    }
  }

  /// The current pattern was already asked for (once per screen).
  bool _routeFetched = false;

  Future<void> _fetchRoute(String patternId) async {
    try {
      final pattern = await _operations.routePattern(patternId);
      if (!mounted) return;
      final planned = _trip?.plannedPattern;
      if (planned == null) {
        setState(() => _useRoute(pattern));
      } else if (pattern.hasGeometry) {
        // The trip's own stops and times, with the Dashboard's line.
        setState(() => _useRoute(planned.withGeometry(pattern.geometry)));
      }
    } on Exception catch (_) {
      // No route (or no line): the map keeps what it has.
    }
  }

  void _useRoute(RoutePattern pattern) {
    if (pattern.path.isEmpty && pattern.locatedStops.isEmpty) return;
    _route = pattern;
    _nextStop = NextStopTracker(pattern.stops);
    final snap = _sender.snapshot.value;
    if (snap.latitude != null && snap.longitude != null) {
      _nextStop!.update(snap.latitude!, snap.longitude!);
    }
    unawaited(_drawRoute());
  }

  /// The driver's trip already in progress, if any.
  Future<void> _loadActiveTrip() async {
    setState(() {
      _loadingTrip = true;
      _tripError = null;
    });
    try {
      final trips = await _operations.driverTrips(
        status: TripStatus.inProgress,
      );
      if (!mounted) return;
      setState(() => _setTrip(trips.firstOrNull));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.type == ApiErrorType.unauthorized) {
        await _onSessionExpired();
        return;
      }
      setState(() => _tripError = e.message);
    } finally {
      if (mounted) setState(() => _loadingTrip = false);
    }
  }

  // --- Map ---------------------------------------------------------------------

  void _onMapReady(PassengerMapHandle map) {
    _map = map;
    _drawnBus = null;
    unawaited(_drawRoute());
    _onBusPosition(_sender.snapshot.value);
  }

  Future<void> _drawRoute() async {
    final map = _map;
    final route = _route;
    if (map == null || route == null) return;
    await map.showRoute(route);
    await map.highlightStop(_nextStop?.next);
    final snap = _sender.snapshot.value;
    if (snap.latitude == null || snap.longitude == null || !_follow) {
      await _fitRoute();
    }
  }

  Future<void> _fitRoute() async {
    final map = _map;
    final route = _route;
    if (map == null || route == null) return;
    final snap = _sender.snapshot.value;
    await map.fitBounds([
      ...route.path,
      if (snap.latitude != null && snap.longitude != null)
        GeoPoint(snap.latitude!, snap.longitude!),
    ], padding: const EdgeInsets.all(48));
  }

  /// New GPS reading: moves the bus, advances the next stop, follows it.
  void _onBusPosition(TripTrackingSnapshot snap) {
    final lat = snap.latitude;
    final lng = snap.longitude;
    if (lat == null || lng == null) return;
    final tracker = _nextStop;
    if (tracker != null && tracker.update(lat, lng)) {
      if (mounted) setState(() {});
      unawaited(_map?.highlightStop(tracker.next));
    }
    final map = _map;
    if (map == null || _drawnBus == (lat, lng)) return;
    _drawnBus = (lat, lng);
    unawaited(map.showBus(BusMarker(latitude: lat, longitude: lng)));
    if (_follow) unawaited(map.moveTo(lat, lng, zoom: _followZoom));
  }

  /// "Centrar en el bus": follows the bus again.
  void _centerOnBus() {
    final snap = _sender.snapshot.value;
    setState(() => _follow = true);
    if (snap.latitude != null && snap.longitude != null) {
      unawaited(
        _map?.moveTo(snap.latitude!, snap.longitude!, zoom: _followZoom),
      );
    }
  }

  /// "Ver ruta completa": the whole route, and stops following the bus.
  void _showWholeRoute() {
    setState(() => _follow = false);
    unawaited(_fitRoute());
  }

  // --- Session -----------------------------------------------------------------

  /// Stops the GPS, clears the session and goes to Login (only once).
  Future<void> _onSessionExpired() async {
    if (_signingOut || !mounted) return;
    _signingOut = true;
    _sender.stop();
    // The token is already invalid: no need to call POST /auth/logout.
    await _session.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(sessionExpiredMessage),
        behavior: SnackBarBehavior.floating,
        backgroundColor: SmartBusColors.error,
      ),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  // --- GPS ---------------------------------------------------------------------

  /// Sends the GPS of the trip. Only a trip the Dashboard already confirmed
  /// as `in_progress`: the start itself (`POST .../start`) happens on Home,
  /// after the confirmation and the location check.
  Future<void> _start() async {
    final trip = _trip;
    if (trip == null || _busy) return;
    if (trip.status != TripStatus.inProgress) {
      setState(() => _tripError = 'Este viaje ya no está en curso.');
      return;
    }
    setState(() => _tripError = null);
    final current = _sender.snapshot.value;
    if (current.isTracking) {
      if (current.tripId == trip.id) return; // already sending this trip
      _sender.stop(); // a trip that is no longer the active one
    }
    await _sender.start(tripId: trip.id);
  }

  /// "Finalizar recorrido": asks first. "Cancelar" or a tap outside → nothing
  /// is sent and the GPS keeps sending.
  Future<void> _stop() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('finish-trip-dialog'),
        title: const Text('¿Finalizar el recorrido?'),
        content: const Text(
          'Se dejará de enviar la ubicación del autobús y el viaje quedará '
          'como finalizado.',
        ),
        actions: [
          TextButton(
            key: const Key('finish-trip-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('finish-trip-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: SmartBusColors.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _complete();
  }

  /// `POST ops/trips/{id}/complete`. The GPS keeps sending until the
  /// Dashboard answers: it only stops once the trip is no longer running
  /// (completed, or it turns out it was cancelled / is not the driver's).
  /// Trip whose end position was already sent ([TripLocationSender.sendFinal]).
  String? _finalSentFor;

  Future<void> _complete() async {
    final trip = _trip;
    if (trip == null || _busy || !mounted) return;
    setState(() {
      _busy = true;
      _tripError = null;
    });
    try {
      // The end position, stored by the GPS service; it must arrive while
      // the trip is still in progress (best effort, never blocks finishing).
      // Once per trip, also when "Reintentar" calls this again.
      if (_finalSentFor != trip.id &&
          _sender.snapshot.value.tripId == trip.id) {
        _finalSentFor = trip.id;
        await _sender.sendFinal();
      }
      // 200 also when it was already completed (e.g. from another device).
      final done = await _operations.completeTrip(trip.id);
      if (!mounted) return;
      if (done.status != TripStatus.inProgress) _sender.stop();
      setState(() => _trip = done.withPlannedPattern(trip.plannedPattern));
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.type) {
        case ApiErrorType.unauthorized:
          await _onSessionExpired();
        case ApiErrorType.conflict:
          // Not in progress (scheduled / cancelled): backend message.
          _showError(e.message);
          await _refreshTrip(trip.id);
        case ApiErrorType.forbidden || ApiErrorType.notFound:
          _sender.stop();
          setState(() => _cannotComplete = true);
          _showError(cannotCompleteMessage);
        default:
          // No connection, timeout, 429, 5xx…: still in progress, the GPS
          // keeps sending (pending locations stay queued). Try again.
          _showError(e.message, onRetry: _complete);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// After a 409: the trip's real status. If it is no longer running
  /// (cancelled, completed, scheduled), the GPS stops and the screen says so.
  Future<void> _refreshTrip(String tripId) async {
    try {
      final fresh = await _operations.trip(tripId);
      if (!mounted || fresh.status == TripStatus.inProgress) return;
      _sender.stop();
      setState(() => _trip = fresh.withPlannedPattern(_trip?.plannedPattern));
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.unauthorized) await _onSessionExpired();
      // Otherwise keep what is shown: the driver can try again.
    }
  }

  void _showError(String message, {VoidCallback? onRetry}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: SmartBusColors.error,
          action: onRetry == null
              ? null
              : SnackBarAction(
                  label: 'Reintentar',
                  textColor: SmartBusColors.blanco,
                  onPressed: onRetry,
                ),
        ),
      );
  }

  void _goHome() => Navigator.pushReplacementNamed(context, '/driver/home');

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        _goHome();
      case 1:
        Navigator.pushReplacementNamed(context, '/driver/routes');
      case 2:
        return; // already here
      case 3:
        Navigator.pushReplacementNamed(context, '/driver/account');
    }
  }

  // --- UI ----------------------------------------------------------------------

  /// The trip is running (or can be resumed): map + panel.
  bool get _onRoute {
    final trip = _trip;
    // While completing, the map and the GPS stay (the button shows a spinner).
    return trip != null &&
        trip.status == TripStatus.inProgress &&
        !_loadingTrip &&
        !_cannotComplete;
  }

  @override
  Widget build(BuildContext context) {
    final onRoute = _onRoute;
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      bottomNavigationBar: DriverBottomNav(currentIndex: 2, onTap: _onTabTap),
      body: Column(
        children: [
          SmartBusHeader(
            title: 'Recorrido',
            subtitle: _trip?.title,
            type: SmartBusUserType.driver,
            compact: onRoute,
          ),
          Expanded(
            child: onRoute
                ? _routeView(_trip!)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                    child: _statusView(),
                  ),
          ),
        ],
      ),
    );
  }

  /// Map on top (most of the screen), compact panel below.
  Widget _routeView(DriverTrip trip) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            key: const Key('trip-map'),
            children: [
              Positioned.fill(
                child: widget.mapBuilder(
                  context,
                  PassengerMapOptions(
                    mode: MapMode.streets,
                    onReady: _onMapReady,
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Column(
                  children: [
                    if (_route != null) ...[
                      _MapButton(
                        key: const Key('fit-route'),
                        icon: Icons.route_outlined,
                        tooltip: 'Ver ruta completa',
                        onPressed: _showWholeRoute,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _MapButton(
                      key: const Key('center-bus'),
                      icon: _follow
                          ? Icons.my_location
                          : Icons.location_searching,
                      tooltip: 'Centrar en el bus',
                      onPressed: _centerOnBus,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TripChip(trip: trip),
                    if (_route == null) ...[
                      const SizedBox(height: 8),
                      const _MapNote(
                        'Este viaje no tiene la ruta dibujada; se muestra '
                        'solo la posición del bus.',
                      ),
                    ] else if (!_route!.hasGeometry) ...[
                      const SizedBox(height: 8),
                      const ApproximateRouteNote(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        ValueListenableBuilder<TripTrackingSnapshot>(
          valueListenable: _sender.snapshot,
          builder: (context, snap, _) => _TripPanel(
            trip: trip,
            snap: snap,
            nextStop: _nextStop,
            tripError: _tripError,
            onResume: _start,
            onStop: _stop,
            completing: _busy,
          ),
        ),
      ],
    );
  }

  /// Loading, no trip, not started, finished or completion failed.
  Widget _statusView() {
    final trip = _trip;
    if (_loadingTrip) {
      return const Center(child: CircularProgressIndicator());
    }
    if (trip == null) {
      return _BlockedView(
        icon: Icons.event_busy_outlined,
        title: 'Sin recorrido en curso',
        message:
            _tripError ??
            'Elige tu viaje del día en Inicio para empezar el recorrido.',
        actionLabel: 'Ir a Inicio',
        onAction: _goHome,
      );
    }
    if (_cannotComplete) {
      return _BlockedView(
        icon: Icons.block,
        title: cannotCompleteMessage,
        message:
            'Este viaje no está asignado a tu cuenta o ya no existe. '
            'Ya no se envía la ubicación.',
        actionLabel: 'Ir a Inicio',
        onAction: _goHome,
      );
    }
    if (trip.status == TripStatus.scheduled) {
      return _BlockedView(
        icon: Icons.schedule,
        title: 'El viaje aún no ha iniciado',
        message: 'Inícialo desde Inicio con "Iniciar recorrido".',
        actionLabel: 'Ir a Inicio',
        onAction: _goHome,
      );
    }
    return _FinishedView(
      trip: trip,
      sentCount: _sender.snapshot.value.sentCount,
      onHome: _goHome,
    );
  }
}

// ---------------------------------------------------------------------------

/// Compact panel under the map. Tracking: status line, next stop, the
/// "no cierres la app" notice and "Finalizar recorrido". Otherwise, why the
/// GPS is not sending and how to fix it.
class _TripPanel extends StatelessWidget {
  const _TripPanel({
    required this.trip,
    required this.snap,
    required this.nextStop,
    required this.tripError,
    required this.onResume,
    required this.onStop,
    required this.completing,
  });

  final DriverTrip trip;
  final TripTrackingSnapshot snap;
  final NextStopTracker? nextStop;
  final String? tripError;
  final VoidCallback onResume;
  final VoidCallback onStop;

  /// `POST .../complete` is waiting for the Dashboard.
  final bool completing;

  /// "Finalizar recorrido" (red, spinner while completing).
  Widget get _finishButton => _PanelButton(
    key: const Key('finish-trip'),
    label: completing ? 'Finalizando…' : 'Finalizar recorrido',
    icon: Icons.stop_rounded,
    color: SmartBusColors.error,
    loading: completing,
    onPressed: onStop,
  );

  /// The trip is still in progress while the GPS is paused: it can be ended
  /// too (e.g. the driver reached the end after reopening the app).
  Widget get _finishLink => Center(
    child: TextButton.icon(
      key: const Key('finish-trip'),
      onPressed: completing ? null : onStop,
      icon: completing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.stop_rounded, color: SmartBusColors.error),
      label: Text(
        completing ? 'Finalizando…' : 'Finalizar recorrido',
        style: const TextStyle(color: SmartBusColors.error),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('trip-panel'),
      color: SmartBusColors.blanco,
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _stateContent(context),
        ),
      ),
    );
  }

  List<Widget> _stateContent(BuildContext context) {
    switch (snap.state) {
      case TripTrackingState.tracking:
        return [
          _SendingLine(snap: snap),
          if (snap.lastError != null) ...[
            const SizedBox(height: 4),
            _ErrorLine(
              message: snap.pendingCount > 0
                  ? 'Sin conexión estable: se reintentará el envío.'
                  : snap.lastError!,
            ),
          ],
          if (nextStop != null && nextStop!.stops.isNotEmpty) ...[
            const SizedBox(height: 8),
            _NextStopCard(tracker: nextStop!, departureAt: trip.departureAt),
          ],
          const SizedBox(height: 8),
          const KeepAppOpenNotice(compact: true),
          const SizedBox(height: 8),
          _finishButton,
        ];
      case TripTrackingState.starting:
        return [
          const _PanelMessage(
            icon: Icons.gps_fixed,
            title: 'Solicitando permiso…',
            message: 'Preparando el envío de la ubicación.',
            busy: true,
          ),
        ];
      case TripTrackingState.permissionDenied:
        return [
          const _PanelMessage(
            icon: Icons.location_off_outlined,
            title: 'Permiso de ubicación denegado',
            message:
                'Actívalo en los ajustes de la app para enviar la posición del '
                'autobús.',
          ),
          const SizedBox(height: 10),
          _PanelButton(
            label: 'Abrir ajustes',
            icon: Icons.settings_outlined,
            onPressed: Geolocator.openAppSettings,
          ),
        ];
      case TripTrackingState.locationServicesDisabled:
        return [
          const _PanelMessage(
            icon: Icons.gps_off,
            title: 'Ubicación desactivada',
            message: 'Activa la ubicación (GPS) del dispositivo.',
          ),
          const SizedBox(height: 10),
          _PanelButton(
            label: 'Activar ubicación',
            icon: Icons.gps_fixed,
            onPressed: Geolocator.openLocationSettings,
          ),
        ];
      case TripTrackingState.rejected:
        return [
          _PanelMessage(
            icon: Icons.block,
            title: 'No se puede enviar la ubicación',
            message: snap.lastError ?? 'El servidor rechazó la ubicación.',
          ),
          const SizedBox(height: 10),
          _PanelButton(
            label: 'Reintentar',
            icon: Icons.refresh,
            onPressed: onResume,
          ),
          _finishLink,
        ];
      case TripTrackingState.idle || TripTrackingState.stopped:
        final error = snap.lastError ?? tripError;
        return [
          _PanelMessage(
            icon: Icons.pause_circle_outline,
            title: 'No se está enviando la ubicación',
            message:
                error ??
                'Continúa el recorrido para que los pasajeros vean el bus.',
            isError: error != null,
          ),
          const SizedBox(height: 10),
          _PanelButton(
            label: 'Continuar recorrido',
            icon: Icons.play_arrow_rounded,
            onPressed: onResume,
          ),
          _finishLink,
        ];
    }
  }
}

/// Chip over the map: "Hacia … · Inició 13:05 · Bus …" (the route name is
/// already in the header).
class _TripChip extends StatelessWidget {
  const _TripChip({required this.trip});

  final DriverTrip trip;

  @override
  Widget build(BuildContext context) {
    // The backend's actual departure (local time), not the device's clock.
    final actual = trip.actualDepartureAt;
    final departure = trip.scheduledDepartureAt;
    final details = [
      if (trip.headsign != null) 'Hacia ${trip.headsign}',
      if (actual != null)
        'Inició ${formatHour(actual)}'
      else if (departure != null)
        'Salida ${formatHour(departure)}',
      ?trip.busLabel,
    ];
    if (details.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('trip-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SmartBusColors.blanco.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.directions_bus_filled,
            color: SmartBusColors.azulPrincipal,
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              details.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SmartBusColors.grisOscuro,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "● Enviando ubicación · hace 3 s" + small sent / pending counters.
class _SendingLine extends StatelessWidget {
  const _SendingLine({required this.snap});

  final TripTrackingSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final pending = snap.pendingCount > 0;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: pending ? SmartBusColors.retraso : SmartBusColors.verdeMenta,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Enviando ubicación',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: ' · ${_lastSentLabel(snap)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _Counter(
          key: const Key('sent-count'),
          icon: Icons.cloud_done_outlined,
          value: snap.sentCount,
          tooltip: 'Enviadas',
        ),
        const SizedBox(width: 6),
        _Counter(
          key: const Key('pending-count'),
          icon: Icons.sync,
          value: snap.pendingCount,
          tooltip: 'Pendientes',
          highlight: pending,
        ),
      ],
    );
  }

  static String _lastSentLabel(TripTrackingSnapshot snap) {
    final at = snap.lastSentAt;
    if (at == null) return 'sin confirmar';
    final secs = DateTime.now().difference(at).inSeconds;
    if (secs <= 1) return 'hace un momento';
    if (secs < 60) return 'hace $secs s';
    return 'hace ${secs ~/ 60} min';
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    super.key,
    required this.icon,
    required this.value,
    required this.tooltip,
    this.highlight = false,
  });

  final IconData icon;
  final int value;
  final String tooltip;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? SmartBusColors.retraso
        : SmartBusColors.azulPrincipal;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Próxima parada: Centro · Parada 2 de 5 · 13:12".
class _NextStopCard extends StatelessWidget {
  const _NextStopCard({required this.tracker, required this.departureAt});

  final NextStopTracker tracker;
  final DateTime? departureAt;

  @override
  Widget build(BuildContext context) {
    final stop = tracker.next;
    final index = tracker.nextIndex;
    final total = tracker.stops.length;
    final String label;
    final String title;
    final String detail;
    if (tracker.finished) {
      label = 'Fin del recorrido';
      title = 'Llegaste a la última parada';
      detail = 'Finaliza el recorrido cuando termines.';
    } else if (stop == null || index == null) {
      label = 'Paradas';
      title = '$total paradas en este recorrido';
      detail = 'Esperando la ubicación del bus…';
    } else {
      label = index == 0 ? 'Primera parada' : 'Próxima parada';
      title = stop.name;
      final minutes = stop.minutesFromStart;
      final at = departureAt;
      detail = [
        'Parada ${index + 1} de $total',
        if (minutes != null && at != null)
          'programada ${formatHour(at.add(Duration(minutes: minutes)))}',
      ].join(' · ');
    }
    return Container(
      key: const Key('next-stop'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SmartBusColors.verdeTurquesa.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            tracker.finished ? Icons.flag : Icons.place,
            color: SmartBusColors.verdeTurquesa,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: SmartBusColors.grisOscuro,
                  ),
                ),
                Text(
                  '$label · $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + title + message, small (for the panel).
class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.busy = false,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool busy;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        else
          Icon(icon, color: SmartBusColors.retraso, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                message,
                style: TextStyle(
                  color: isError ? SmartBusColors.error : Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-width, 42 px high button of the panel.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color = SmartBusColors.azulPrincipal,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final FutureOr<void> Function() onPressed;
  final Color color;

  /// Shows a spinner instead of the icon and ignores taps.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: FilledButton.icon(
        onPressed: loading ? null : () => onPressed(),
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SmartBusColors.blanco,
                ),
              )
            : Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: SmartBusColors.blanco,
          disabledBackgroundColor: color.withValues(alpha: 0.7),
          disabledForegroundColor: SmartBusColors.blanco,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Small round button over the map.
class _MapButton extends StatelessWidget {
  const _MapButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: tooltip,
      tooltip: tooltip,
      backgroundColor: SmartBusColors.blanco,
      foregroundColor: SmartBusColors.azulPrincipal,
      elevation: 3,
      shape: const CircleBorder(),
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}

/// Note over the map (e.g. the trip has no route to draw).
class _MapNote extends StatelessWidget {
  const _MapNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('no-route-note'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SmartBusColors.blanco.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ---------------------------------------------------------------------------

/// Completed (with the backend's arrival time, in local time) or cancelled.
class _FinishedView extends StatelessWidget {
  const _FinishedView({
    required this.trip,
    required this.sentCount,
    required this.onHome,
  });

  final DriverTrip trip;
  final int sentCount;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final cancelled = trip.status == TripStatus.cancelled;
    // The Dashboard's actual_arrival_at, never the phone clock.
    final arrival = cancelled ? null : trip.actualArrivalAt;
    return Column(
      key: const Key('trip-finished'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          cancelled ? Icons.cancel_outlined : Icons.check_circle_outline,
          size: 64,
          color: cancelled ? SmartBusColors.error : SmartBusColors.completado,
        ),
        const SizedBox(height: 16),
        Text(
          cancelled ? 'Viaje cancelado' : 'Recorrido finalizado',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (arrival != null) ...[
          const SizedBox(height: 6),
          Text(
            'Llegada: ${formatHour(arrival)}',
            key: const Key('trip-arrival'),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          sentCount > 0
              ? 'Se enviaron $sentCount ubicaciones.'
              : 'El viaje ya no está en curso.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onHome, child: const Text('Volver a Inicio')),
      ],
    );
  }
}

class _BlockedView extends StatelessWidget {
  const _BlockedView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final FutureOr<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: SmartBusColors.retraso),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => onAction(), child: Text(actionLabel)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// "No cierres SmartBus" notice: the GPS keeps sending in the background or
/// with the screen locked, but **not** if the app is swiped away from the
/// recent apps (Android stops it). Shown on the start confirmation and, as a
/// single line ([compact]), in the trip panel.
class KeepAppOpenNotice extends StatelessWidget {
  const KeepAppOpenNotice({super.key, this.compact = false});

  /// One short line (the trip panel) instead of title + explanation.
  final bool compact;

  static const title = 'No cierres SmartBus durante el recorrido';
  static const message =
      'Puedes bloquear la pantalla o usar otras apps. Si cierras SmartBus '
      'desde las apps recientes, se deja de enviar la ubicación del bus.';
  @override
  Widget build(BuildContext context) {
    final notice = _notice();
    if (!compact) return notice;
    // One line in the panel; a tap explains why.
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(title),
          content: const Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      ),
      child: notice,
    );
  }

  Widget _notice() {
    return Container(
      key: const Key('keep-app-open-notice'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 12,
      ),
      decoration: BoxDecoration(
        color: SmartBusColors.advertencia.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
      ),
      child: Row(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.phonelink_lock_outlined,
            color: SmartBusColors.advertencia,
            size: compact ? 16 : 20,
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: compact
                ? Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
          if (compact) ...[
            const SizedBox(width: 6),
            Icon(Icons.info_outline, size: 15, color: Colors.grey.shade600),
          ],
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, size: 16, color: SmartBusColors.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: SmartBusColors.error, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
