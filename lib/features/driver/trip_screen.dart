import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/operations_service.dart';
import '../trip_tracking/models/trip_tracking.dart';
import '../trip_tracking/services/trip_location_sender.dart';

/// Arguments of the `/driver/trip` route.
class TripScreenArgs {
  const TripScreenArgs({required this.trip, this.autoStart = false});

  final DriverTrip trip;
  final bool autoStart;
}

/// Driver screen for a trip (issue-4) with the real Dashboard trip.
///
/// "Iniciar recorrido" first starts the trip in the Dashboard
/// (`POST ops/trips/{id}/start`, so it becomes `in_progress`) and then sends
/// the bus GPS location every few seconds ([TripLocationSender]). "Finalizar
/// recorrido" stops the GPS and completes the trip (`POST .../complete`).
///
/// Opened from the "Recorrido" tab without a trip, it looks for the driver's
/// trip that is already in progress (e.g. the app was closed mid-trip).
class TripScreen extends StatefulWidget {
  const TripScreen({
    super.key,
    this.trip,
    this.autoStart = false,
    this.operations,
    this.sender,
  });

  /// The trip picked on the home tab; `null` = look for the one in progress.
  final DriverTrip? trip;

  /// When `true`, the trip starts as soon as the screen opens (the driver
  /// tapped "Iniciar recorrido" on the home tab).
  final bool autoStart;

  final OperationsService? operations;

  /// Tests plug in a fake (the real one needs the device GPS).
  final TripLocationSender? sender;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  late final TripLocationSender _sender =
      widget.sender ??
      TripLocationSender(
        interval: Duration(seconds: ApiConfig.gpsIntervalSeconds),
      );
  late final OperationsService _operations =
      widget.operations ?? OperationsService();
  Timer? _ticker; // rebuilds every second so "hace Ns" stays fresh

  DriverTrip? _trip;
  bool _loadingTrip = false;

  /// A call to the Dashboard (start / complete) is running.
  bool _busy = false;

  /// Last Dashboard error (start, complete or loading the trip).
  String? _tripError;

  /// The GPS stopped but the Dashboard did not complete the trip.
  bool _completeFailed = false;

  @override
  void initState() {
    super.initState();
    _sender.snapshot.addListener(_onSnapshot);
    _trip = widget.trip;
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
    _sender.snapshot.removeListener(_onSnapshot);
    _sender.dispose();
    super.dispose();
  }

  void _onSnapshot() {
    final tracking = _sender.snapshot.value.isTracking;
    if (tracking && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!tracking) {
      _ticker?.cancel();
      _ticker = null;
    }
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
      setState(() => _trip = trips.firstOrNull);
    } on ApiException catch (e) {
      if (mounted) setState(() => _tripError = e.message);
    } finally {
      if (mounted) setState(() => _loadingTrip = false);
    }
  }

  /// Starts the trip in the Dashboard (if still scheduled), then the GPS.
  Future<void> _start() async {
    var trip = _trip;
    if (trip == null || _busy) return;

    if (trip.status == TripStatus.scheduled) {
      setState(() {
        _busy = true;
        _tripError = null;
      });
      try {
        trip = await _operations.startTrip(trip.id);
      } on ApiException catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _tripError = e.message;
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _trip = trip;
      });
    }

    if (trip.status != TripStatus.inProgress) {
      setState(() => _tripError = 'Este viaje ya no está en curso.');
      return;
    }
    setState(() => _tripError = null);
    await _sender.start(tripId: trip.id);
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar recorrido'),
        content: const Text(
          '¿Seguro que quieres finalizar el recorrido? Se dejará de enviar la '
          'ubicación del autobús y el viaje quedará finalizado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _sender.stop();
      await _complete();
    }
  }

  /// Completes the trip in the Dashboard (the GPS is already stopped).
  Future<void> _complete() async {
    final trip = _trip;
    if (trip == null || !mounted) return;
    setState(() {
      _busy = true;
      _tripError = null;
      _completeFailed = false;
    });
    try {
      final done = await _operations.completeTrip(trip.id);
      if (!mounted) return;
      setState(() => _trip = done);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _tripError = e.message;
        _completeFailed = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      bottomNavigationBar: DriverBottomNav(currentIndex: 2, onTap: _onTabTap),
      body: Column(
        children: [
          SmartBusHeader(
            title: 'Recorrido',
            subtitle: _trip?.title,
            type: SmartBusUserType.driver,
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: SmartBusColors.blanco,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: _content(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
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
    if (_busy) {
      return _BusyView(
        label: trip.status == TripStatus.scheduled
            ? 'Iniciando el viaje…'
            : 'Finalizando el viaje…',
      );
    }
    if (_completeFailed) {
      return _BlockedView(
        icon: Icons.sync_problem,
        title: 'No se pudo finalizar el viaje',
        message:
            '${_tripError ?? ''}\nYa no se envía la ubicación; '
            'reintenta para cerrar el viaje.',
        actionLabel: 'Reintentar',
        onAction: _complete,
      );
    }
    if (trip.status.isFinished) {
      return _FinishedView(
        trip: trip,
        sentCount: _sender.snapshot.value.sentCount,
        onHome: _goHome,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TripSummary(trip: trip),
        const SizedBox(height: 16),
        Expanded(
          child: ValueListenableBuilder<TripTrackingSnapshot>(
            valueListenable: _sender.snapshot,
            builder: (context, snap, _) => _Body(
              snap: snap,
              startLabel: trip.status == TripStatus.inProgress
                  ? 'Continuar recorrido'
                  : 'Iniciar recorrido',
              tripError: _tripError,
              onStart: _start,
              onStop: _stop,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.snap,
    required this.startLabel,
    required this.tripError,
    required this.onStart,
    required this.onStop,
  });

  final TripTrackingSnapshot snap;
  final String startLabel;

  /// Error of the Dashboard (e.g. the trip could not be started).
  final String? tripError;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return switch (snap.state) {
      TripTrackingState.tracking => _TrackingView(snap: snap, onStop: onStop),
      TripTrackingState.permissionDenied => _BlockedView(
        icon: Icons.location_off_outlined,
        title: 'Permiso de ubicación denegado',
        message:
            'Actívalo en los ajustes de la app para poder enviar la posición '
            'del autobús durante el recorrido.',
        actionLabel: 'Abrir ajustes',
        onAction: Geolocator.openAppSettings,
      ),
      TripTrackingState.rejected => _BlockedView(
        icon: Icons.block,
        title: 'No se puede enviar la ubicación',
        message: snap.lastError ?? 'El servidor rechazó la ubicación.',
        actionLabel: 'Reintentar',
        onAction: onStart,
      ),
      TripTrackingState.locationServicesDisabled => _BlockedView(
        icon: Icons.gps_off,
        title: 'Ubicación desactivada',
        message:
            'Activa la ubicación (GPS) del dispositivo e inténtalo de nuevo.',
        actionLabel: 'Activar ubicación',
        onAction: Geolocator.openLocationSettings,
      ),
      _ => _IdleView(
        snap: snap,
        startLabel: startLabel,
        error: snap.lastError ?? tripError,
        onStart: onStart,
      ),
    };
  }
}

// ---------------------------------------------------------------------------

class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.snap,
    required this.startLabel,
    required this.error,
    required this.onStart,
  });

  final TripTrackingSnapshot snap;
  final String startLabel;
  final String? error;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final starting = snap.state == TripTrackingState.starting;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.navigation_outlined,
          size: 64,
          color: SmartBusColors.azulPrincipal.withValues(alpha: 0.35),
        ),
        const SizedBox(height: 16),
        Text(
          'Listo para iniciar',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Al iniciar, se enviará la ubicación del autobús cada pocos '
          'segundos hasta que termines el recorrido.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        GradientButton(
          label: starting ? 'Solicitando permiso…' : startLabel,
          icon: Icons.play_arrow_rounded,
          busy: starting,
          onPressed: starting ? null : onStart,
        ),
        if (error != null && !starting) ...[
          const SizedBox(height: 14),
          _ErrorLine(message: error!),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Route, destination and planned times of the trip.
class _TripSummary extends StatelessWidget {
  const _TripSummary({required this.trip});

  final DriverTrip trip;

  @override
  Widget build(BuildContext context) {
    final departure = trip.scheduledDepartureAt;
    final details = [
      if (trip.headsign != null) 'Hacia ${trip.headsign}',
      if (departure != null) 'Salida ${formatHour(departure)}',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SmartBusColors.grisClaro,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.directions_bus_filled,
            color: SmartBusColors.azulPrincipal,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusyView extends StatelessWidget {
  const _BusyView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

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
    return Column(
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

// ---------------------------------------------------------------------------

class _TrackingView extends StatelessWidget {
  const _TrackingView({required this.snap, required this.onStop});

  final TripTrackingSnapshot snap;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SmartBusColors.verdeTurquesa.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.my_location, color: SmartBusColors.verdeMenta),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enviando ubicación',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _lastSentLabel(snap),
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
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Enviadas',
                value: '${snap.sentCount}',
                icon: Icons.cloud_done_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Pendientes',
                value: '${snap.pendingCount}',
                icon: Icons.sync,
                highlight: snap.pendingCount > 0,
              ),
            ),
          ],
        ),
        if (snap.pendingCount > 0) ...[
          const SizedBox(height: 10),
          Text(
            'Sin conexión estable. Se reintentará el envío automáticamente.',
            style: const TextStyle(color: SmartBusColors.retraso, fontSize: 13),
          ),
          if (snap.lastError != null) ...[
            const SizedBox(height: 6),
            _ErrorLine(message: snap.lastError!),
          ],
        ],
        if (snap.lastError != null && snap.pendingCount == 0) ...[
          const SizedBox(height: 12),
          _ErrorLine(message: snap.lastError!),
        ],
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop_rounded, size: 22),
            label: const Text('Finalizar recorrido'),
            style: FilledButton.styleFrom(
              backgroundColor: SmartBusColors.error,
              foregroundColor: SmartBusColors.blanco,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _lastSentLabel(TripTrackingSnapshot snap) {
    final at = snap.lastSentAt;
    if (at == null) return 'Aún sin confirmar…';
    final secs = DateTime.now().difference(at).inSeconds;
    if (secs <= 1) return 'Última confirmada: hace un momento';
    if (secs < 60) return 'Última confirmada: hace ${secs}s';
    return 'Última confirmada: hace ${secs ~/ 60}m';
  }
}

// ---------------------------------------------------------------------------

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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? SmartBusColors.retraso
        : SmartBusColors.azulPrincipal;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, size: 18, color: SmartBusColors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: SmartBusColors.error, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
