import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/map_config.dart';
import '../../core/location/location_service.dart';
import '../../core/theme.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/nearby_routes_filter.dart' show formatDistance;
import '../operations/services/next_stop_tracker.dart';
import '../operations/services/operations_service.dart';
import '../trip_tracking/models/trip_arrival_estimate.dart';
import '../trip_tracking/models/trip_tracking.dart';
import '../trip_tracking/services/live_trip_tracker.dart';
import 'map/map_overlay.dart';
import 'map/passenger_map.dart';
import 'map/route_sheet.dart' show StopsTimeline;

export '../trip_tracking/services/live_trip_tracker.dart'
    show LiveTripTrackerFactory;

/// Passenger: follows the bus of a trip in real time on the map (HU3).
///
/// The position comes from [LiveTripTracker] (GET + `BusLocationUpdated`
/// events); this screen only draws its state and how fresh it is. The
/// passenger's own position is drawn too, so they can see where the bus is
/// relative to them.
///
/// **Route:** the line and stops the bus follows (`GET ops/public/trips/{id}`
/// for its pattern, then `GET ops/route-patterns/{id}`), drawn like on the
/// home map. The first view shows the whole route with the bus; "Ver el bus"
/// follows the bus (the camera moves with every new position) and "Ver ruta"
/// goes back to the whole route.
class BusTrackingScreen extends StatefulWidget {
  const BusTrackingScreen({
    super.key,
    required this.tripId,
    this.routePatternId,
    this.operations,
    this.trackerFactory,
    this.mapBuilder = buildMapLibrePassengerMap,
    this.locationService = const LocationService(),
    this.clock = DateTime.now,
  });

  /// UUID of the trip to follow (picked in "Buses en curso").
  final String tripId;

  /// Pattern of the trip when the caller knows it; otherwise it is asked
  /// (`GET ops/public/trips/{id}`).
  final String? routePatternId;

  /// Catalogue (trip pattern and route); tests plug in a fake.
  final OperationsService? operations;

  final LiveTripTrackerFactory? trackerFactory;
  final PassengerMapBuilder mapBuilder;

  /// The passenger's location. Only shown if the permission was already
  /// granted (the passenger home asks for it); this screen never asks.
  final LocationService locationService;

  /// "Now" for the freshness of the position (tests move it by hand). Must be
  /// the same clock as the tracker's.
  final DateTime Function() clock;

  @override
  State<BusTrackingScreen> createState() => _BusTrackingScreenState();
}

class _BusTrackingScreenState extends State<BusTrackingScreen> {
  late final LiveTripTracker _tracker;
  PassengerMapHandle? _map;
  Timer? _ticker; // "hace Ns" and live -> stale without new events
  DeviceLocation? _userLocation;
  StreamSubscription<DeviceLocation>? _userLocationSub;

  /// The route the bus follows; `null` while unknown (or not available).
  RoutePattern? _route;

  /// The camera moves with the bus ("Ver el bus"); off while the passenger
  /// looks at the whole route.
  bool _follow = true;

  /// The first view (route + bus, or the bus alone) was already set.
  bool _framed = false;

  /// Last bus position the camera moved to (the ticker redraws every second).
  (double, double)? _followed;

  /// Which stops the bus already passed (from its position).
  NextStopTracker? _busStops;

  /// Where the passenger should go: the closest stop the bus has not passed.
  BoardingStop? _boarding;

  /// Location permission of this screen; `null` while checking.
  LocationAccess? _locationAccess;

  String get _tripId => widget.tripId;

  /// The map widget, built once (see build).
  Widget? _mapWidget;

  @override
  void initState() {
    super.initState();
    _tracker = (widget.trackerFactory ?? LiveTripTracker.withDefaults)(_tripId);
    _tracker.state.addListener(_onState);
    _tracker.arrivals.addListener(_onState);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onState());
    unawaited(_tracker.start());
    unawaited(_followUserLocation());
    unawaited(_loadRoute());
  }

  /// The pattern of the trip, then its line and stops. Optional: without it
  /// the map still shows the bus.
  Future<void> _loadRoute() async {
    final operations = widget.operations ?? OperationsService();
    try {
      final patternId =
          widget.routePatternId ??
          (await operations.publicTrip(_tripId)).routePatternId;
      if (patternId == null) return;
      final route = await operations.routePattern(patternId);
      if (!mounted || route.path.isEmpty) return;
      final busStops = NextStopTracker(route.stops);
      // The bus usually arrives first: place it on the route right away.
      final position = _tracker.state.value.position;
      if (position != null) {
        busStops.update(position.latitude, position.longitude);
      }
      setState(() {
        _route = route;
        _busStops = busStops;
      });
      _updateBoarding();
      await _drawRoute();
    } catch (_) {
      // No route: bus only.
    }
  }

  Future<void> _drawRoute() async {
    final map = _map;
    final route = _route;
    if (map == null || route == null) return;
    await map.showRoute(route);
    await map.highlightStop(_boarding?.stop);
    // The first time: the whole route with the bus inside it (even if the
    // camera was already on the bus, which usually arrives first).
    if (!_routeFramed) {
      _routeFramed = true;
      _framed = true;
      if (mounted) setState(() => _follow = false);
      await _fitRoute();
    }
  }

  /// The whole route was shown once.
  bool _routeFramed = false;

  /// First view while there is no route: the bus.
  void _frame() {
    if (_framed || _map == null) return;
    if (_tracker.state.value.position == null) return;
    _framed = true;
    _centerOnBus();
  }

  Future<void> _fitRoute() async {
    final map = _map;
    final route = _route;
    if (map == null || route == null) return;
    final position = _tracker.state.value.position;
    final user = _userLocation;
    await map.fitBounds([
      ...route.path,
      if (position != null) GeoPoint(position.latitude, position.longitude),
      if (user != null) GeoPoint(user.latitude, user.longitude),
    ], padding: const EdgeInsets.all(48));
  }

  /// "Cómo llegar": the passenger, their stop and the bus in one view.
  void _showWayToStop() {
    final map = _map;
    final boarding = _boarding;
    final user = _userLocation;
    if (map == null || boarding == null || user == null) return;
    final position = _tracker.state.value.position;
    setState(() => _follow = false);
    unawaited(
      map.fitBounds([
        GeoPoint(user.latitude, user.longitude),
        boarding.stop.location!,
        if (position != null) GeoPoint(position.latitude, position.longitude),
      ], padding: const EdgeInsets.all(64)),
    );
  }

  /// Recomputes the passenger's stop (bus moved, passenger moved, route
  /// loaded) and highlights it on the map when it changes.
  void _updateBoarding() {
    final tracker = _busStops;
    final user = _userLocation;
    final next = tracker == null || user == null
        ? null
        : boardingStopFor(tracker, user.latitude, user.longitude);
    final previous = _boarding;
    final changed =
        !identical(previous?.stop, next?.stop) ||
        previous?.stopsAway != next?.stopsAway ||
        (previous?.walkMeters.round() ?? -1) !=
            (next?.walkMeters.round() ?? -1);
    if (!changed) return;
    if (mounted) setState(() => _boarding = next);
    if (!identical(previous?.stop, next?.stop)) {
      unawaited(_map?.highlightStop(next?.stop));
    }
  }

  /// "Ver ruta": the whole route; the camera stops following the bus.
  void _showRoute() {
    setState(() => _follow = false);
    unawaited(_fitRoute());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _userLocationSub?.cancel();
    _tracker.state.removeListener(_onState);
    _tracker.arrivals.removeListener(_onState);
    _tracker.dispose();
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    setState(() {});
    _drawBus();
  }

  void _onMapReady(PassengerMapHandle map) {
    _map = map;
    final user = _userLocation;
    if (user != null) map.showUserLocation(user);
    unawaited(_drawRoute());
    _drawBus();
  }

  /// Draws the passenger's position (and follows it) when the permission is
  /// already granted. It is not asked on opening: the panel offers
  /// "Activar ubicación" ([_enableLocation]) to find the closest stop.
  Future<void> _followUserLocation({bool request = false}) async {
    final service = widget.locationService;
    final access = await service.checkAccess(request: request);
    if (!mounted) return;
    setState(() => _locationAccess = access);
    if (access != LocationAccess.granted) return;
    final current = await service.currentLocation();
    if (!mounted) return;
    if (current != null) _onUserLocation(current);
    await _userLocationSub?.cancel();
    _userLocationSub = service.watch().listen(
      _onUserLocation,
      onError: (Object _) {}, // keep the last position on GPS errors
    );
  }

  /// "Activar ubicación": asks for the permission, or opens the settings
  /// when it can no longer be asked (denied forever, GPS off).
  Future<void> _enableLocation() async {
    final access = _locationAccess;
    if (access == LocationAccess.deniedForever ||
        access == LocationAccess.serviceDisabled) {
      await widget.locationService.openSettings(access!);
    }
    await _followUserLocation(request: true);
  }

  void _onUserLocation(DeviceLocation location) {
    if (!mounted) return;
    final first = _userLocation == null;
    _userLocation = location;
    _map?.showUserLocation(location);
    _updateBoarding();
    // The first position after the route: show it with the route.
    if (first && _routeFramed && !_follow) unawaited(_fitRoute());
  }

  void _drawBus() {
    final map = _map;
    if (map == null) return;
    final state = _tracker.state.value;
    final position = state.position;
    if (position == null || state.phase == LiveTripPhase.finished) {
      map.showBus(null);
      return;
    }
    // Which stops the bus already passed → the passenger's stop.
    if (_busStops?.update(position.latitude, position.longitude) ?? false) {
      _updateBoarding();
    }
    final freshness = state.freshnessAt(widget.clock());
    map.showBus(
      BusMarker(
        latitude: position.latitude,
        longitude: position.longitude,
        live: freshness == TrackingFreshness.live,
      ),
    );
    if (!_framed) {
      _frame();
      return;
    }
    // Following: the camera moves with each new position (not every redraw).
    final at = (position.latitude, position.longitude);
    if (_follow && _followed != at) {
      _followed = at;
      map.moveTo(position.latitude, position.longitude);
    }
  }

  /// "Ver el bus": centers on the bus and follows it.
  void _centerOnBus() {
    final position = _tracker.state.value.position;
    final map = _map;
    if (position == null || map == null) return;
    if (!_follow && mounted) setState(() => _follow = true);
    _follow = true;
    _followed = (position.latitude, position.longitude);
    map.moveTo(position.latitude, position.longitude, zoom: MapConfig.userZoom);
  }

  void _showStopsModal() {
    final route = _route;
    if (route == null || route.stops.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          key: const Key('stops-modal'),
          decoration: const BoxDecoration(
            color: SmartBusColors.blanco,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              StopsTimeline(
                colors: MapOverlayColors.sheet,
                pattern: route,
                arrivals: _tracker.arrivals.value,
                selected: _busStops?.nextStop,
                onSelect: (stop) {
                  Navigator.pop(context);
                  if (stop.location != null) {
                    _map?.moveTo(
                      stop.location!.latitude,
                      stop.location!.longitude,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The "Próxima parada" card: only with a route to know which stop is next.
  Widget? _nextStopCard(LiveTripState state) {
    final tracker = _busStops;
    if (tracker == null ||
        tracker.stops.isEmpty ||
        state.phase == LiveTripPhase.finished) {
      return null;
    }
    final next = tracker.nextStop;
    if (next == null) return null;
    final arrivals = _tracker.arrivals.value;
    final estimate = arrivals[next.id] ?? arrivals[next.stopId];
    return _NextStopCard(
      stop: next,
      estimate: estimate,
      onTap: _showStopsModal,
    );
  }

  /// The "Tu parada" card: only with a route to choose a stop from.
  Widget? _boardingCard(LiveTripState state) {
    final tracker = _busStops;
    if (tracker == null ||
        tracker.stops.isEmpty ||
        state.phase == LiveTripPhase.finished) {
      return null;
    }
    final access = _locationAccess;
    if (access == null) return null; // still checking
    if (access != LocationAccess.granted) {
      return _BoardingCard(
        icon: Icons.my_location,
        title: '¿Dónde tomo el bus?',
        lines: const ['Activa tu ubicación para ver la parada más cercana.'],
        actionLabel: access == LocationAccess.denied ? 'Activar' : 'Ajustes',
        onAction: () => unawaited(_enableLocation()),
      );
    }
    if (_userLocation == null) {
      return const _BoardingCard(
        icon: Icons.my_location,
        title: 'Buscando tu ubicación…',
        lines: ['Para mostrarte la parada más cercana.'],
      );
    }
    final boarding = _boarding;
    if (boarding == null) {
      return const _BoardingCard(
        icon: Icons.flag_outlined,
        title: 'El bus ya pasó todas las paradas',
        lines: ['Este bus ya no pasa por ninguna parada más.'],
      );
    }
    final stopsAway = boarding.stopsAway;
    final busLine = switch (stopsAway) {
      null => 'Esperando la posición del bus.',
      0 => 'Es la próxima parada del bus.',
      1 => 'Al bus le falta 1 parada para llegar.',
      _ => 'Al bus le faltan $stopsAway paradas para llegar.',
    };
    return _BoardingCard(
      icon: Icons.directions_walk,
      title: 'Tu parada: ${boarding.stop.name}',
      lines: [
        'A ${formatDistance(boarding.walkMeters)} · '
            '~${boarding.walkMinutes} min caminando',
        busLine,
      ],
      actionLabel: 'Cómo llegar',
      onAction: _showWayToStop,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _tracker.state.value;
    final status = _TripStatusView.of(state, widget.clock());

    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      body: Column(
        children: [
          SmartBusHeader(
            title: 'Rastreando tu bus',
            type: SmartBusUserType.passenger,
            onBack: Navigator.canPop(context)
                ? () => Navigator.pop(context)
                : null,
          ),
          Expanded(
            child: Stack(
              children: [
                // Built once: the screen redraws every second ("hace N s"),
                // the same instance makes Flutter skip the map.
                Positioned.fill(
                  child: _mapWidget ??= widget.mapBuilder(
                    context,
                    PassengerMapOptions(
                      mode: MapMode.streets,
                      onReady: _onMapReady,
                    ),
                  ),
                ),
                const Positioned(
                  left: 12,
                  right: 12,
                  bottom: 6,
                  child: MapAttribution(mode: MapMode.streets),
                ),
                if (_route case final route? when !route.hasGeometry)
                  const Positioned(
                    left: 12,
                    top: 12,
                    right: 12,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ApproximateRouteNote(),
                    ),
                  ),
                Positioned(
                  right: 16,
                  bottom: 24,
                  child: Column(
                    children: [
                      if (_route != null) ...[
                        FloatingActionButton.small(
                          key: const Key('show-stops-button'),
                          heroTag: null,
                          tooltip: 'Ver paradas',
                          backgroundColor: SmartBusColors.blanco,
                          foregroundColor: SmartBusColors.verdePasajero,
                          onPressed: _showStopsModal,
                          child: const Icon(Icons.list_alt_outlined),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          key: const Key('show-route-button'),
                          heroTag: null,
                          tooltip: 'Ver ruta',
                          backgroundColor: SmartBusColors.blanco,
                          foregroundColor: SmartBusColors.verdePasajero,
                          onPressed: _showRoute,
                          child: const Icon(Icons.route_outlined),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (state.position != null &&
                          state.phase != LiveTripPhase.finished)
                        FloatingActionButton.small(
                          key: const Key('center-bus-button'),
                          heroTag: null,
                          tooltip: 'Ver el bus',
                          backgroundColor: SmartBusColors.verdePasajero,
                          foregroundColor: SmartBusColors.blanco,
                          onPressed: _centerOnBus,
                          child: const Icon(Icons.directions_bus_filled),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _StatusPanel(
            nextStopCard: _nextStopCard(state),
            boarding: _boardingCard(state),
            status: status,
            reconnecting:
                state.phase == LiveTripPhase.tracking &&
                !state.realtime &&
                _tracker.feed != null,
            onRetry: state.phase == LiveTripPhase.failed
                ? () => unawaited(_tracker.start())
                : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Texts and colors for a [LiveTripState].
class _TripStatusView {
  const _TripStatusView({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  static const _gray = Color(0xFF6B7280);

  factory _TripStatusView.of(LiveTripState state, DateTime now) {
    switch (state.phase) {
      case LiveTripPhase.loading:
        return const _TripStatusView(
          icon: Icons.search,
          color: SmartBusColors.verdePasajero,
          title: 'Buscando tu bus…',
          message: 'Obteniendo la ubicación del viaje.',
        );
      case LiveTripPhase.notFound:
        return const _TripStatusView(
          icon: Icons.help_outline,
          color: SmartBusColors.error,
          title: 'No encontramos este viaje',
          message: 'Revisa el viaje seleccionado e inténtalo de nuevo.',
        );
      case LiveTripPhase.failed:
        return _TripStatusView(
          icon: Icons.cloud_off,
          color: SmartBusColors.error,
          title: 'No se pudo cargar el viaje',
          message: state.error ?? 'Inténtalo nuevamente.',
        );
      case LiveTripPhase.finished:
        final cancelled = state.status == TripStatus.cancelled;
        return _TripStatusView(
          icon: cancelled ? Icons.cancel_outlined : Icons.check_circle_outline,
          color: cancelled ? SmartBusColors.error : SmartBusColors.completado,
          title: cancelled ? 'Viaje cancelado' : 'Viaje finalizado',
          message: cancelled
              ? 'Este viaje fue cancelado.'
              : 'El bus terminó su recorrido.',
        );
      case LiveTripPhase.tracking:
        break;
    }

    if (state.status != TripStatus.inProgress) {
      return const _TripStatusView(
        icon: Icons.schedule,
        color: SmartBusColors.verdePasajero,
        title: 'El viaje aún no inicia',
        message: 'Verás el bus en el mapa en cuanto salga.',
      );
    }

    final position = state.position;
    final seenAt = state.positionSeenAt;
    if (position == null || seenAt == null) {
      return const _TripStatusView(
        icon: Icons.satellite_alt_outlined,
        color: _gray,
        title: 'Esperando la ubicación del bus',
        message: 'El bus todavía no ha enviado su primera ubicación.',
      );
    }

    final ago = _ago(now.difference(seenAt));
    switch (state.freshnessAt(now)) {
      case TrackingFreshness.live:
        final speed = position.speedKmh;
        return _TripStatusView(
          icon: Icons.directions_bus_filled,
          color: SmartBusColors.verdePasajero,
          title: 'En vivo',
          message: speed != null
              ? 'Actualizado $ago · ${speed.round()} km/h'
              : 'Actualizado $ago',
        );
      case TrackingFreshness.stale:
        return _TripStatusView(
          icon: Icons.signal_cellular_alt_1_bar,
          color: SmartBusColors.advertencia,
          title: 'Señal débil',
          message: 'Última ubicación $ago.',
        );
      case TrackingFreshness.noSignal:
      case TrackingFreshness.notTracking:
        return _TripStatusView(
          icon: Icons.signal_cellular_off,
          color: _gray,
          title: 'Sin señal del bus',
          message: 'Última ubicación $ago.',
        );
    }
  }

  static String _ago(Duration age) {
    final seconds = age.inSeconds < 0 ? 0 : age.inSeconds;
    if (seconds < 5) return 'hace un momento';
    if (seconds < 60) return 'hace $seconds s';
    if (seconds < 3600) return 'hace ${seconds ~/ 60} min';
    return 'hace ${seconds ~/ 3600} h';
  }
}

/// "Tu parada": the stop the passenger should walk to (closest one the bus
/// has not passed), or the button to turn the location on to find it.
class _BoardingCard extends StatelessWidget {
  const _BoardingCard({
    required this.icon,
    required this.title,
    required this.lines,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('boarding-card'),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: SmartBusColors.verdeTurquesa.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: SmartBusColors.verdePasajero),
          const SizedBox(width: 10),
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
                for (final line in lines)
                  Text(
                    line,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              key: const Key('boarding-action'),
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: SmartBusColors.verdePasajero,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NextStopCard extends StatelessWidget {
  const _NextStopCard({
    required this.stop,
    this.estimate,
    this.onTap,
  });

  final PatternStop stop;
  final TripArrivalEstimate? estimate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final est = estimate;
    final hasEta = est != null && est.etaMinutes != null;

    return Container(
      key: const Key('next-stop-card'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: SmartBusColors.verdeTurquesa.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.directions_bus,
                color: SmartBusColors.verdePasajero,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Próxima parada: ${stop.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: SmartBusColors.grisOscuro,
                  ),
                ),
              ),
              if (onTap != null)
                TextButton(
                  key: const Key('view-stops-action'),
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'Ver paradas',
                    style: TextStyle(
                      color: SmartBusColors.verdePasajero,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          if (hasEta) ...[
            const SizedBox(height: 6),
            Container(
              key: const Key('next-stop-eta-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: est.isLive
                    ? SmartBusColors.completado.withValues(alpha: 0.15)
                    : SmartBusColors.azulPrincipal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: est.isLive
                      ? SmartBusColors.completado
                      : SmartBusColors.azulPrincipal,
                  width: 1,
                ),
              ),
              child: Text(
                est.isLive
                    ? 'Llegada en ${est.etaMinutes} min (En vivo)'
                    : 'Llegada estimada en ${est.etaMinutes} min (Itinerario)',
                style: TextStyle(
                  color: est.isLive
                      ? SmartBusColors.completado
                      : SmartBusColors.azulPrincipal,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.status,
    required this.reconnecting,
    this.nextStopCard,
    this.boarding,
    this.onRetry,
  });

  /// "Próxima parada" card, shown above the bus status.
  final Widget? nextStopCard;

  /// "Tu parada" card, shown above the bus status.
  final Widget? boarding;

  final _TripStatusView status;
  final bool reconnecting;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          key: const Key('trip-status-panel'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (nextStopCard != null) ...[
              nextStopCard!,
              const SizedBox(height: 8),
            ],
            if (boarding != null) ...[boarding!, const SizedBox(height: 8)],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: status.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(status.icon, color: status.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status.message,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (reconnecting) ...[
              const SizedBox(height: 10),
              const Row(
                key: Key('reconnecting-hint'),
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Conectando en tiempo real… mientras tanto la ubicación '
                      'se actualiza cada pocos segundos.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: SmartBusColors.verdePasajero,
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
