import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/operations_service.dart';

/// Passenger "Buses en curso": first pick a route (Dashboard catalogue), then
/// [RouteBusesScreen] shows its directions with the buses running now — tap
/// one to follow it live — or just the route (its stops).
class BusesInProgressScreen extends StatefulWidget {
  const BusesInProgressScreen({super.key, this.operations});

  final OperationsService? operations;

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

  void _open(TransitRoute route) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RouteBusesScreen(route: route, operations: _operations),
      ),
    );
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
/// the live tracking) and its stops ("Ver ruta").
class RouteBusesScreen extends StatefulWidget {
  const RouteBusesScreen({super.key, required this.route, this.operations});

  final TransitRoute route;
  final OperationsService? operations;

  @override
  State<RouteBusesScreen> createState() => _RouteBusesScreenState();
}

class _RouteBusesScreenState extends State<RouteBusesScreen> {
  late final OperationsService _operations =
      widget.operations ?? OperationsService();

  List<(RoutePattern, List<LiveBusTrip>)>? _patterns;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final patterns = await _operations.routePatterns(widget.route.id);
      final buses = await Future.wait(
        patterns.map((p) => _operations.ongoingTrips(p.id)),
      );
      if (!mounted) return;
      setState(() {
        _patterns = [
          for (var i = 0; i < patterns.length; i++) (patterns[i], buses[i]),
        ];
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _follow(LiveBusTrip trip) =>
      Navigator.pushNamed(context, '/passenger/tracking', arguments: trip.id);

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
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (_, i) => _PatternCard(
                    pattern: list[i].$1,
                    buses: list[i].$2,
                    onFollow: _follow,
                  ),
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
    required this.onFollow,
  });

  final RoutePattern pattern;
  final List<LiveBusTrip> buses;
  final void Function(LiveBusTrip) onFollow;

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
            if (buses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'No hay buses en curso en este recorrido.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              for (final bus in buses)
                _BusTile(bus: bus, onTap: () => onFollow(bus)),
            Theme(
              // No divider lines around the expansion tile.
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.route,
                  color: SmartBusColors.verdePasajero,
                ),
                title: const Text('Ver ruta'),
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

class _BusTile extends StatelessWidget {
  const _BusTile({required this.bus, required this.onTap});

  final LiveBusTrip bus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final departed = bus.actualDepartureAt ?? bus.scheduledDepartureAt;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: SmartBusColors.blanco,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(
          Icons.directions_bus_filled,
          color: SmartBusColors.verdePasajero,
        ),
        title: Text(bus.busLabel),
        subtitle: departed == null
            ? null
            : Text('En camino desde las ${formatHour(departed)}'),
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
