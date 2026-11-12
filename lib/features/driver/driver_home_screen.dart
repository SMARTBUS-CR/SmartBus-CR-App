import 'package:flutter/material.dart';

import '../../core/location/location_service.dart';
import '../../core/network/api_exception.dart';
import '../../core/platform/notification_permission.dart';
import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/operations_service.dart';
import '../trip_tracking/models/trip_tracking.dart';
import '../trip_tracking/services/active_trip_tracking.dart';
import 'trip_screen.dart';
import 'widgets/trip_status_badge.dart';

/// Driver home ("Inicio" tab): the trips assigned to the driver **today**
/// (Dashboard `driver/trips`), plus any trip of another day that is still in
/// progress.
///
/// "Iniciar recorrido" (only on scheduled trips, and only while no other trip
/// is in progress):
/// 1. asks for confirmation;
/// 2. checks the location permission and services — without them the trip is
///    **not** started, so no trip is left "en curso" without GPS;
/// 3. `POST ops/trips/{id}/start`, with a spinner on the button;
/// 4. on 200 opens the "Recorrido" tab ([TripScreen]) with the started trip,
///    which sends the GPS.
///
/// A rejected start shows the reason in a SnackBar and refreshes the list.
/// "Continuar recorrido" opens the trip in progress.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({
    super.key,
    this.operations,
    this.location = const LocationService(),
    this.notifications = const NotificationPermission(),
    this.sessionStore,
    this.clock = DateTime.now,
  });

  final OperationsService? operations;

  /// Location permission / services check before starting (tests fake it).
  final LocationService location;

  /// Android 13+: asked before starting so the "recorrido activo"
  /// notification is visible. A denial does not block the trip.
  final NotificationPermission notifications;

  /// Cleared when the Gateway answers 401.
  final SecureSessionStore? sessionStore;

  /// "Today" (tests fix it).
  final DateTime Function() clock;

  /// Shown when the start is answered 403 / 404.
  static const notAllowedMessage = 'No puedes iniciar este viaje.';

  /// Shown when there are no trips for today.
  static const noTripsMessage = 'No tienes viajes asignados para hoy.';

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late final OperationsService _operations =
      widget.operations ?? OperationsService();
  late final SecureSessionStore _session =
      widget.sessionStore ?? SecureSessionStore();

  List<DriverTrip>? _trips;
  String? _error;
  bool _loading = true;

  /// Id of the trip whose start request is running (spinner, no double start).
  String? _startingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The trip already in progress, if any (only one per driver).
  DriverTrip? get _activeTrip =>
      _trips?.where((trip) => trip.status == TripStatus.inProgress).firstOrNull;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Today's trips + any trip still in progress from another day (it
      // crossed midnight, or nobody finished it): that one goes first.
      final [today, inProgress] = await Future.wait([
        _operations.driverTrips(serviceDate: widget.clock()),
        _operations.driverTrips(status: TripStatus.inProgress),
      ]);
      final todayIds = {for (final trip in today) trip.id};
      final trips = [
        ...inProgress.where((trip) => !todayIds.contains(trip.id)),
        ...today,
      ];
      if (!mounted) return;
      setState(() => _trips = trips);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.type == ApiErrorType.unauthorized) {
        await _onSessionExpired(e);
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- Start a trip ------------------------------------------------------------

  Future<void> _confirmAndStart(DriverTrip trip) async {
    final departure = trip.scheduledDepartureAt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('confirm-start-dialog'),
        title: const Text('Iniciar recorrido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Iniciar el viaje ${trip.title}'
              '${departure == null ? '' : ' de las ${formatHour(departure)}'}?'
              ' Se registrará la salida y se empezará a enviar la ubicación '
              'del autobús.',
            ),
            const SizedBox(height: 14),
            const KeepAppOpenNotice(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-start'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _start(trip);
  }

  /// Location check, then `POST ops/trips/{id}/start`, then the trip screen.
  Future<void> _start(DriverTrip trip) async {
    if (_startingId != null) return;
    setState(() => _startingId = trip.id);

    // Without location the trip is not started: it would show "en curso" to
    // the passengers without the bus position.
    final access = await widget.location.checkAccess();
    if (!mounted) return;
    if (access != LocationAccess.granted) {
      setState(() => _startingId = null);
      _showLocationNotice(access, trip);
      return;
    }
    // Only so the driver sees the GPS notification; never blocks the start.
    await widget.notifications.request();
    if (!mounted) return;

    final DriverTrip started;
    try {
      started = await _operations.startTrip(trip.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _startingId = null);
      await _onStartError(e, trip);
      return;
    }
    if (!mounted) return;
    setState(() => _startingId = null);

    if (started.status != TripStatus.inProgress) {
      _showSnack('El viaje no quedó en curso. Inténtalo nuevamente.');
      await _load();
      return;
    }
    _openTrip(started);
  }

  Future<void> _onStartError(ApiException e, DriverTrip trip) async {
    switch (e.type) {
      case ApiErrorType.unauthorized:
        await _onSessionExpired(e);
      case ApiErrorType.conflict || ApiErrorType.validation:
        // Not scheduled, bus / driver unavailable, departure suspended,
        // another trip in progress: the backend says why.
        _showSnack(e.message, error: true);
        await _load();
      case ApiErrorType.forbidden || ApiErrorType.notFound:
        _showSnack(DriverHomeScreen.notAllowedMessage, error: true);
        await _load();
      default:
        // No connection, timeout, 429, 5xx: the trip stays scheduled.
        _showSnack(
          e.message,
          error: true,
          actionLabel: 'Reintentar',
          onAction: () => _start(trip),
        );
    }
  }

  void _showLocationNotice(LocationAccess access, DriverTrip trip) {
    final (message, action) = switch (access) {
      LocationAccess.serviceDisabled => (
        'Activa la ubicación (GPS) del dispositivo para iniciar el recorrido.',
        'Activar',
      ),
      LocationAccess.deniedForever => (
        'Permite el acceso a tu ubicación desde los ajustes de la app para '
            'iniciar el recorrido.',
        'Ajustes',
      ),
      _ => (
        'Permite el acceso a tu ubicación para iniciar el recorrido.',
        'Permitir',
      ),
    };
    _showSnack(
      message,
      error: true,
      actionLabel: action,
      onAction: access == LocationAccess.denied
          ? () =>
                _start(trip) // asks for the permission again
          : () => widget.location.openSettings(access),
    );
  }

  Future<void> _onSessionExpired(ApiException e) async {
    ActiveTripTracking.stop(); // the GPS would get 401 too
    // The token is already invalid: no need to call POST /auth/logout.
    await _session.clear();
    if (!mounted) return;
    _showSnack(e.message, error: true);
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  void _openTrip(DriverTrip trip) {
    Navigator.pushReplacementNamed(
      context,
      '/driver/trip',
      arguments: TripScreenArgs(trip: trip, autoStart: true),
    );
  }

  void _showSnack(
    String message, {
    bool error = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? SmartBusColors.error : null,
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: SmartBusColors.blanco,
                onPressed: onAction,
              ),
      ),
    );
  }

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        return; // already on Home
      case 1:
        Navigator.pushReplacementNamed(context, '/driver/routes');
        return;
      case 2:
        Navigator.pushReplacementNamed(context, '/driver/trip');
        return;
      case 3:
        Navigator.pushReplacementNamed(context, '/driver/account');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      bottomNavigationBar: DriverBottomNav(currentIndex: 0, onTap: _onTabTap),
      body: Column(
        children: [
          const SmartBusHeader(
            title: 'Mi ruta del día',
            type: SmartBusUserType.driver,
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final trips = _trips;
    if (_loading && trips == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && trips == null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar tus viajes',
        message: _error!,
        actionLabel: 'Reintentar',
        onAction: _load,
      );
    }
    if (trips == null || trips.isEmpty) {
      return _Message(
        icon: Icons.event_available_outlined,
        title: DriverHomeScreen.noTripsMessage,
        message: 'Cuando el administrador te asigne un viaje aparecerá aquí.',
        actionLabel: 'Actualizar',
        onAction: _load,
      );
    }
    final active = _activeTrip;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemCount: trips.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final trip = trips[i];
          return _TripCard(
            trip: trip,
            action: _actionFor(trip, active),
            starting: _startingId == trip.id,
            enabled: _startingId == null,
            onStart: () => _confirmAndStart(trip),
            onContinue: () => _openTrip(trip),
          );
        },
      ),
    );
  }

  _TripAction _actionFor(DriverTrip trip, DriverTrip? active) {
    switch (trip.status) {
      case TripStatus.inProgress:
        return _TripAction.resume;
      case TripStatus.scheduled:
        return active == null ? _TripAction.start : _TripAction.blocked;
      default:
        return _TripAction.none;
    }
  }
}

// ---------------------------------------------------------------------------

/// What a trip card offers.
enum _TripAction {
  /// "Iniciar recorrido" (scheduled, no other trip in progress).
  start,

  /// "Continuar recorrido" (the trip in progress).
  resume,

  /// Scheduled, but another trip is in progress.
  blocked,

  /// Completed or cancelled.
  none,
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.action,
    required this.starting,
    required this.enabled,
    required this.onStart,
    required this.onContinue,
  });

  final DriverTrip trip;
  final _TripAction action;

  /// Its start request is running.
  final bool starting;

  /// `false` while any start request is running.
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final departure = trip.scheduledDepartureAt;
    final arrival = trip.scheduledArrivalAt;
    final actual = trip.actualDepartureAt;
    final secondary = TextStyle(color: Colors.grey.shade700);

    return Container(
      key: Key('trip-card-${trip.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SmartBusColors.grisClaro,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.directions_bus_filled,
                color: SmartBusColors.azulPrincipal,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trip.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TripStatusBadge.forStatus(trip.status),
            ],
          ),
          if (trip.headsign != null) ...[
            const SizedBox(height: 4),
            Text('Hacia ${trip.headsign}', style: secondary),
          ],
          if (trip.busLabel != null) ...[
            const SizedBox(height: 4),
            Text(trip.busLabel!, style: secondary),
          ],
          if (departure != null) ...[
            const SizedBox(height: 4),
            Text(
              arrival == null
                  ? 'Salida ${formatHour(departure)}'
                  : 'Salida ${formatHour(departure)} · '
                        'Llegada ${formatHour(arrival)}',
              style: secondary,
            ),
          ],
          // The backend's actual departure, in local time (not the device's).
          if (actual != null && trip.status == TripStatus.inProgress) ...[
            const SizedBox(height: 4),
            Text(
              'Inició a las ${formatHour(actual)}',
              style: const TextStyle(
                color: SmartBusColors.verdeMenta,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (trip.plannedPattern?.stops.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            TripStopsList(trip: trip),
          ],
          ..._action(context),
        ],
      ),
    );
  }

  List<Widget> _action(BuildContext context) {
    switch (action) {
      case _TripAction.start:
        return [
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: Key('start-trip-${trip.id}'),
              onPressed: enabled ? onStart : null,
              icon: starting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        key: Key('start-trip-spinner'),
                        strokeWidth: 2,
                        color: SmartBusColors.blanco,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(starting ? 'Iniciando…' : 'Iniciar recorrido'),
            ),
          ),
        ];
      case _TripAction.resume:
        return [
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: Key('continue-trip-${trip.id}'),
              onPressed: enabled ? onContinue : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Continuar recorrido'),
            ),
          ),
        ];
      case _TripAction.blocked:
        return [
          const SizedBox(height: 10),
          Row(
            key: Key('trip-blocked-${trip.id}'),
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Finaliza el recorrido en curso para iniciar este viaje.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            ],
          ),
        ];
      case _TripAction.none:
        return const [];
    }
  }
}

/// "Ver paradas (N)": the stops of the trip in travel order, with the
/// scheduled time at each one (departure + `minutes_from_start`), from the
/// route planned for the trip (`planned_route_snapshot`). Collapsed by default
/// so the trip list stays short.
class TripStopsList extends StatefulWidget {
  const TripStopsList({super.key, required this.trip});

  final DriverTrip trip;

  @override
  State<TripStopsList> createState() => _TripStopsListState();
}

class _TripStopsListState extends State<TripStopsList> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final stops = trip.plannedPattern?.stops ?? const <PatternStop>[];
    final departure = trip.scheduledDepartureAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('trip-stops-${trip.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: SmartBusColors.azulPrincipal,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _open ? 'Ocultar paradas' : 'Ver paradas (${stops.length})',
                    style: const TextStyle(
                      color: SmartBusColors.azulPrincipal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  color: SmartBusColors.azulPrincipal,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (var i = 0; i < stops.length; i++)
            _StopRow(
              key: Key('trip-stop-${trip.id}-$i'),
              number: i + 1,
              name: stops[i].name,
              time: switch ((departure, stops[i].minutesFromStart)) {
                (final DateTime at, final int minutes) => formatHour(
                  at.add(Duration(minutes: minutes)),
                ),
                _ => null,
              },
              first: i == 0,
              last: i == stops.length - 1,
            ),
      ],
    );
  }
}

/// One stop: number on a small vertical line, name and scheduled time.
class _StopRow extends StatelessWidget {
  const _StopRow({
    super.key,
    required this.number,
    required this.name,
    required this.time,
    required this.first,
    required this.last,
  });

  final int number;
  final String name;
  final String? time;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final edge = first || last;
    final color = first
        ? SmartBusColors.verdeTurquesa
        : (last ? SmartBusColors.azulPrincipal : Colors.grey.shade500);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The line joining the stops.
                Positioned(
                  top: first ? 14 : 0,
                  bottom: last ? 14 : 0,
                  child: Container(width: 2, color: Colors.grey.shade300),
                ),
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: edge ? color : SmartBusColors.blanco,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: edge ? SmartBusColors.blanco : color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: edge ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
          if (time != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 5),
              child: Text(
                time!,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
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
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: SmartBusColors.azulPrincipal.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
