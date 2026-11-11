import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/operations_service.dart';
import '../trip_tracking/models/trip_tracking.dart';
import 'trip_screen.dart';

/// Driver home ("Inicio" tab): the trips assigned to the driver **today**
/// (Dashboard `driver/trips`), plus any trip of another day that is still in
/// progress. "Iniciar recorrido" opens the "Recorrido" tab
/// ([TripScreen]) with that trip, which starts it in the Dashboard and then
/// sends the GPS.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({
    super.key,
    this.operations,
    this.clock = DateTime.now,
  });

  final OperationsService? operations;

  /// "Today" (tests fix it).
  final DateTime Function() clock;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late final OperationsService _operations =
      widget.operations ?? OperationsService();

  List<DriverTrip>? _trips;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openTrip(DriverTrip trip) {
    Navigator.pushReplacementNamed(
      context,
      '/driver/trip',
      arguments: TripScreenArgs(trip: trip, autoStart: true),
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
        title: 'No tienes viajes asignados hoy',
        message: 'Cuando el administrador te asigne un viaje aparecerá aquí.',
        actionLabel: 'Actualizar',
        onAction: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemCount: trips.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) =>
            _TripCard(trip: trips[i], onOpen: () => _openTrip(trips[i])),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onOpen});

  final DriverTrip trip;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final (label, color) = tripStatusBadge(trip.status);
    final departure = trip.scheduledDepartureAt;
    final arrival = trip.scheduledArrivalAt;
    final canOpen =
        trip.status == TripStatus.scheduled ||
        trip.status == TripStatus.inProgress;

    return Container(
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
              _Badge(label: label, color: color),
            ],
          ),
          if (trip.headsign != null) ...[
            const SizedBox(height: 4),
            Text(
              'Hacia ${trip.headsign}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
          if (departure != null) ...[
            const SizedBox(height: 4),
            Text(
              arrival == null
                  ? 'Salida ${formatHour(departure)}'
                  : 'Salida ${formatHour(departure)} · '
                        'Llegada ${formatHour(arrival)}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
          if (canOpen) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  trip.status == TripStatus.inProgress
                      ? 'Continuar recorrido'
                      : 'Iniciar recorrido',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Text and color of a trip status, shared by the driver screens.
(String, Color) tripStatusBadge(TripStatus status) => switch (status) {
  TripStatus.scheduled => ('Programado', SmartBusColors.azulPrincipal),
  TripStatus.inProgress => ('En curso', SmartBusColors.verdeMenta),
  TripStatus.completed => ('Finalizado', SmartBusColors.completado),
  TripStatus.cancelled => ('Cancelado', SmartBusColors.error),
  TripStatus.unknown => ('—', Colors.grey),
};

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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
