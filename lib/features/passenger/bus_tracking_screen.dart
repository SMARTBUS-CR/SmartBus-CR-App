import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/map_config.dart';
import '../../core/location/location_service.dart';
import '../../core/theme.dart';
import '../../widgets/smartbus_header.dart';
import '../trip_tracking/models/trip_tracking.dart';
import '../trip_tracking/services/gps_location_service.dart';
import '../trip_tracking/services/live_trip_tracker.dart';
import '../trip_tracking/services/trip_live_feed.dart';
import 'map/map_overlay.dart';
import 'map/passenger_map.dart';

/// Builds the tracker of a trip (tests plug in fakes).
typedef LiveTripTrackerFactory = LiveTripTracker Function(String tripId);

/// Passenger: follows the bus of a trip in real time on the map (HU3).
///
/// The position comes from [LiveTripTracker] (GET + `BusLocationUpdated`
/// events); this screen only draws its state and how fresh it is. The
/// passenger's own position is drawn too, so they can see where the bus is
/// relative to them.
class BusTrackingScreen extends StatefulWidget {
  const BusTrackingScreen({
    super.key,
    required this.tripId,
    this.trackerFactory,
    this.mapBuilder = buildMapLibrePassengerMap,
    this.locationService = const LocationService(),
    this.clock = DateTime.now,
  });

  /// UUID of the trip to follow (picked in "Buses en curso").
  final String tripId;

  final LiveTripTrackerFactory? trackerFactory;
  final PassengerMapBuilder mapBuilder;

  /// The passenger's location. Only shown if the permission was already
  /// granted (the passenger home asks for it); this screen never asks.
  final LocationService locationService;

  /// "Now" for the freshness of the position (tests move it by hand). Must be
  /// the same clock as the tracker's.
  final DateTime Function() clock;

  static LiveTripTracker _defaultTracker(String tripId) {
    final service = GpsLocationService();
    return LiveTripTracker(
      tripId: tripId,
      service: service,
      feed: ReverbTripFeed.fromConfig(service: service),
    );
  }

  @override
  State<BusTrackingScreen> createState() => _BusTrackingScreenState();
}

class _BusTrackingScreenState extends State<BusTrackingScreen> {
  late final LiveTripTracker _tracker;
  PassengerMapHandle? _map;
  Timer? _ticker; // "hace Ns" and live -> stale without new events
  bool _centeredOnBus = false;
  DeviceLocation? _userLocation;
  StreamSubscription<DeviceLocation>? _userLocationSub;

  String get _tripId => widget.tripId;

  @override
  void initState() {
    super.initState();
    _tracker = (widget.trackerFactory ?? BusTrackingScreen._defaultTracker)(
      _tripId,
    );
    _tracker.state.addListener(_onState);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onState());
    unawaited(_tracker.start());
    unawaited(_followUserLocation());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _userLocationSub?.cancel();
    _tracker.state.removeListener(_onState);
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
    _drawBus();
  }

  /// Draws the passenger's position (and follows it) when the permission is
  /// already granted. Without permission the screen works the same, bus only.
  Future<void> _followUserLocation() async {
    final service = widget.locationService;
    if (await service.checkAccess(request: false) != LocationAccess.granted) {
      return;
    }
    final current = await service.currentLocation();
    if (!mounted) return;
    if (current != null) _onUserLocation(current);
    _userLocationSub = service.watch().listen(
      _onUserLocation,
      onError: (Object _) {}, // keep the last position on GPS errors
    );
  }

  void _onUserLocation(DeviceLocation location) {
    if (!mounted) return;
    _userLocation = location;
    _map?.showUserLocation(location);
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
    final freshness = state.freshnessAt(widget.clock());
    map.showBus(
      BusMarker(
        latitude: position.latitude,
        longitude: position.longitude,
        live: freshness == TrackingFreshness.live,
      ),
    );
    if (!_centeredOnBus) _centerOnBus();
  }

  void _centerOnBus() {
    final position = _tracker.state.value.position;
    final map = _map;
    if (position == null || map == null) return;
    _centeredOnBus = true;
    map.moveTo(position.latitude, position.longitude, zoom: MapConfig.userZoom);
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
            subtitle: status.headerSubtitle,
            type: SmartBusUserType.passenger,
            compact: true,
            onBack: Navigator.canPop(context)
                ? () => Navigator.pop(context)
                : null,
          ),
          Expanded(
            child: Stack(
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
                const Positioned(
                  left: 12,
                  right: 12,
                  bottom: 6,
                  child: MapAttribution(mode: MapMode.streets),
                ),
                if (state.position != null &&
                    state.phase != LiveTripPhase.finished)
                  Positioned(
                    right: 16,
                    bottom: 24,
                    child: FloatingActionButton.small(
                      key: const Key('center-bus-button'),
                      heroTag: null,
                      tooltip: 'Ver el bus',
                      backgroundColor: SmartBusColors.verdePasajero,
                      foregroundColor: SmartBusColors.blanco,
                      onPressed: _centerOnBus,
                      child: const Icon(Icons.directions_bus_filled),
                    ),
                  ),
              ],
            ),
          ),
          _StatusPanel(
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
    this.headerSubtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String? headerSubtitle;

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
          headerSubtitle: cancelled ? 'Cancelado' : 'Finalizado',
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
        headerSubtitle: 'Programado',
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
        headerSubtitle: 'En curso',
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
          headerSubtitle: 'En curso',
        );
      case TrackingFreshness.stale:
        return _TripStatusView(
          icon: Icons.signal_cellular_alt_1_bar,
          color: SmartBusColors.advertencia,
          title: 'Señal débil',
          message: 'Última ubicación $ago.',
          headerSubtitle: 'En curso',
        );
      case TrackingFreshness.noSignal:
      case TrackingFreshness.notTracking:
        return _TripStatusView(
          icon: Icons.signal_cellular_off,
          color: _gray,
          title: 'Sin señal del bus',
          message: 'Última ubicación $ago.',
          headerSubtitle: 'En curso',
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

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.status,
    required this.reconnecting,
    this.onRetry,
  });

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
