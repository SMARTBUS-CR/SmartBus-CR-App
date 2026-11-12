import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/next_stop_tracker.dart';
import '../operations/services/operations_service.dart';
import '../trip_tracking/models/trip_tracking.dart';
import '../trip_tracking/services/route_live_buses.dart';
import 'favorite_star.dart';
import 'map/route_sheet.dart' show liveBusStatus;
import 'services/favorites_controller.dart';

/// Passenger "Buses en curso": first pick a route (Dashboard catalogue), then
/// [RouteBusesScreen] shows its directions with the buses running now — tap
/// one to follow it live — or just the route (its stops).
class BusesInProgressScreen extends StatefulWidget {
  const BusesInProgressScreen({
    super.key,
    this.operations,
    this.liveBusesFactory,
  });

  final OperationsService? operations;

  /// Passed on to [RouteBusesScreen.liveBusesFactory].
  final RouteLiveBuses Function(String patternId)? liveBusesFactory;

  @override
  State<BusesInProgressScreen> createState() => _BusesInProgressScreenState();
}

class _BusesInProgressScreenState extends State<BusesInProgressScreen> {
  late final OperationsService _operations =
      widget.operations ?? OperationsService();

  List<TransitRoute>? _routes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final routes = await _operations.routes();
      if (mounted) setState(() => _routes = routes);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// "Ver ruta" in [RouteBusesScreen] closes both screens and hands the
  /// [RouteSelection] to the passenger home, which draws it on the map.
  Future<void> _open(TransitRoute route) async {
    final selection = await Navigator.push<RouteSelection>(
      context,
      MaterialPageRoute<RouteSelection>(
        builder: (_) => RouteBusesScreen(
          route: route,
          operations: _operations,
          liveBusesFactory: widget.liveBusesFactory,
        ),
      ),
    );
    if (selection != null && mounted) Navigator.pop(context, selection);
  }

  @override
  Widget build(BuildContext context) {
    final routes = _routes;
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      body: Column(
        children: [
          SmartBusHeader(
            title: 'Buses en curso',
            subtitle: 'Elige una ruta',
            type: SmartBusUserType.passenger,
            compact: true,
            onBack: Navigator.canPop(context)
                ? () => Navigator.pop(context)
                : null,
          ),
          Expanded(
            child: switch ((routes, _error)) {
              (null, final String error) => PassengerMessage(
                icon: Icons.cloud_off_outlined,
                title: 'No se pudieron cargar las rutas',
                message: error,
                actionLabel: 'Reintentar',
                onAction: _load,
              ),
              (null, _) => const Center(child: CircularProgressIndicator()),
              (final list?, _) when list.isEmpty => PassengerMessage(
                icon: Icons.route_outlined,
                title: 'No hay rutas disponibles',
                message: 'Todavía no hay rutas publicadas.',
                actionLabel: 'Actualizar',
                onAction: _load,
              ),
              (final list?, _) => RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) =>
                      _RouteTile(route: list[i], onTap: () => _open(list[i])),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.route, required this.onTap});

  final TransitRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        constraints: const BoxConstraints(minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: SmartBusColors.verdePasajero,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          route.code,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: SmartBusColors.blanco,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(route.name),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// ---------------------------------------------------------------------------

/// One route: each direction with the buses running now ("Ver en vivo" opens
/// the live tracking), its stops ("Ver paradas") and "Ver ruta", which pops
/// with a [RouteSelection] so the home map draws that direction.
class RouteBusesScreen extends StatefulWidget {
  const RouteBusesScreen({
    super.key,
    required this.route,
    this.operations,
    this.favorites,
    this.liveBusesFactory,
    this.clock = DateTime.now,
  });

  final TransitRoute route;
  final OperationsService? operations;

  /// For the favorite star; defaults to [FavoritesController.shared].
  final FavoritesController? favorites;

  /// Buses of each direction, with their live status and position; by default
  /// [RouteLiveBuses] (the same the home map uses). Tests plug in fakes.
  final RouteLiveBuses Function(String patternId)? liveBusesFactory;

  /// "Now" for "hace N s"; the same clock as the trackers'.
  final DateTime Function() clock;

  @override
  State<RouteBusesScreen> createState() => _RouteBusesScreenState();
}

class _RouteBusesScreenState extends State<RouteBusesScreen> {
  late final OperationsService _operations =
      widget.operations ?? OperationsService();

  List<(RoutePattern, RouteLiveBuses)>? _patterns;
  String? _error;

  /// Next stop of each bus (by trip id), from its positions.
  final Map<String, NextStopTracker> _nextStops = {};

  /// Redraws "hace N s" and live -> weak signal without new events.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _hasBuses) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _disposeLive();
    super.dispose();
  }

  bool get _hasBuses =>
      _patterns?.any((p) => p.$2.state.value.buses.isNotEmpty) ?? false;

  void _disposeLive() {
    for (final (_, live)
        in _patterns ?? const <(RoutePattern, RouteLiveBuses)>[]) {
      live.dispose();
    }
    _nextStops.clear();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final patterns = await _operations.routePatterns(widget.route.id);
      if (!mounted) return;
      _disposeLive();
      final factory =
          widget.liveBusesFactory ??
          (id) => RouteLiveBuses(patternId: id, operations: _operations);
      final live = [for (final p in patterns) (p, factory(p.id))];
      setState(() => _patterns = live);
      await Future.wait([for (final (_, buses) in live) buses.start()]);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _refresh() async {
    final patterns = _patterns;
    if (patterns == null) return _load();
    await Future.wait([for (final (_, buses) in patterns) buses.refresh()]);
  }

  /// The bus's next stop on [pattern], from its last position.
  PatternStop? _nextStopOf(RoutePattern pattern, LiveBus bus) {
    final position = bus.state.position;
    if (position == null) return null;
    final tracker = _nextStops.putIfAbsent(
      bus.trip.id,
      () => NextStopTracker(pattern.stops),
    );
    tracker.update(position.latitude, position.longitude);
    return tracker.next;
  }

  void _follow(LiveBusTrip trip) =>
      Navigator.pushNamed(context, '/passenger/tracking', arguments: trip.id);

  void _showOnMap(RoutePattern pattern) {
    final patterns = <RoutePattern>[
      for (final (p, _) in _patterns ?? const <(RoutePattern, Object)>[]) p,
    ];
    Navigator.pop(
      context,
      RouteSelection(
        route: widget.route.withPatterns(patterns),
        pattern: pattern,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patterns = _patterns;
    final route = widget.route;
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      body: Column(
        children: [
          SmartBusHeader(
            title: route.code,
            subtitle: route.name,
            type: SmartBusUserType.passenger,
            compact: true,
            onBack: () => Navigator.pop(context),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FavoriteStarButton(
                route: route,
                controller: widget.favorites,
                showLabel: true,
              ),
            ),
          ),
          Expanded(
            child: switch ((patterns, _error)) {
              (null, final String error) => PassengerMessage(
                icon: Icons.cloud_off_outlined,
                title: 'No se pudo cargar la ruta',
                message: error,
                actionLabel: 'Reintentar',
                onAction: _load,
              ),
              (null, _) => const Center(child: CircularProgressIndicator()),
              (final list?, _) when list.isEmpty => PassengerMessage(
                icon: Icons.route_outlined,
                title: 'Esta ruta no tiene recorridos',
                message: 'Todavía no hay recorridos publicados para esta ruta.',
                actionLabel: 'Actualizar',
                onAction: _load,
              ),
              (final list?, _) => RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (_, i) {
                    final (pattern, live) = list[i];
                    return ValueListenableBuilder<RouteLiveBusesState>(
                      valueListenable: live.state,
                      builder: (_, state, _) => _PatternCard(
                        pattern: pattern,
                        buses: state,
                        now: widget.clock(),
                        nextStopOf: (bus) => _nextStopOf(pattern, bus),
                        onFollow: _follow,
                        onShowRoute: () => _showOnMap(pattern),
                      ),
                    );
                  },
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _PatternCard extends StatelessWidget {
  const _PatternCard({
    required this.pattern,
    required this.buses,
    required this.now,
    required this.nextStopOf,
    required this.onFollow,
    required this.onShowRoute,
  });

  final RoutePattern pattern;
  final RouteLiveBusesState buses;
  final DateTime now;
  final PatternStop? Function(LiveBus) nextStopOf;
  final void Function(LiveBusTrip) onFollow;
  final VoidCallback onShowRoute;

  @override
  Widget build(BuildContext context) {
    final duration = pattern.drivingDurationSeconds;
    final info = [
      '${pattern.stops.length} paradas',
      if (duration != null) '~${(duration / 60).round()} min',
    ].join(' · ');

    // Material (not a colored Container) so the tiles' taps show.
    return Material(
      color: SmartBusColors.grisClaro,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pattern.label, style: Theme.of(context).textTheme.titleMedium),
            Text(info, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            if (buses.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (buses.buses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  buses.error ?? 'No hay buses en curso en este recorrido.',
                  key: Key('no-buses-${pattern.id}'),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              for (final bus in buses.buses)
                _BusTile(
                  bus: bus,
                  now: now,
                  nextStop: nextStopOf(bus),
                  onTap: () => onFollow(bus.trip),
                ),
            ListTile(
              key: Key('show-route-${pattern.id}'),
              contentPadding: EdgeInsets.zero,
              onTap: onShowRoute,
              leading: const Icon(
                Icons.map_outlined,
                color: SmartBusColors.verdePasajero,
              ),
              title: const Text('Ver ruta'),
              subtitle: const Text('Recorrido y paradas en el mapa'),
              trailing: const Icon(Icons.chevron_right),
            ),
            Theme(
              // No divider lines around the expansion tile.
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.format_list_numbered,
                  color: SmartBusColors.verdePasajero,
                ),
                title: const Text('Ver paradas'),
                children: [
                  for (final stop in pattern.stops) _StopTile(stop: stop),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bus: its unit/plate, live status ("En vivo · hace 5 s"), where it is
/// ("Próxima parada: Centro") and since when it runs.
class _BusTile extends StatelessWidget {
  const _BusTile({
    required this.bus,
    required this.now,
    required this.nextStop,
    required this.onTap,
  });

  final LiveBus bus;
  final DateTime now;
  final PatternStop? nextStop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trip = bus.trip;
    final departed = trip.actualDepartureAt ?? trip.scheduledDepartureAt;
    final live = bus.state.freshnessAt(now) == TrackingFreshness.live;
    final muted = TextStyle(color: Colors.grey.shade700, fontSize: 13);
    return Card(
      key: Key('bus-${trip.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: SmartBusColors.blanco,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          Icons.directions_bus_filled,
          color: live ? SmartBusColors.verdePasajero : const Color(0xFF9CA3AF),
        ),
        title: Text(trip.busLabel),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              liveBusStatus(bus, now),
              key: Key('bus-status-${trip.id}'),
              style: muted,
            ),
            if (nextStop != null)
              Text(
                'Próxima parada: ${nextStop!.name}',
                key: Key('bus-next-stop-${trip.id}'),
                style: muted,
              ),
            if (departed != null)
              Text('En camino desde las ${formatHour(departed)}', style: muted),
          ],
        ),
        trailing: const Text(
          'Ver en vivo',
          style: TextStyle(
            color: SmartBusColors.verdePasajero,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.stop});

  final PatternStop stop;

  @override
  Widget build(BuildContext context) {
    final minutes = stop.minutesFromStart;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.location_on_outlined, size: 20),
      title: Text(stop.name),
      trailing: minutes == null ? null : Text('+$minutes min'),
    );
  }
}

/// Centered icon + message + action, for loading errors and empty lists.
class PassengerMessage extends StatelessWidget {
  const PassengerMessage({
    super.key,
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
            color: SmartBusColors.verdePasajero.withValues(alpha: 0.35),
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
