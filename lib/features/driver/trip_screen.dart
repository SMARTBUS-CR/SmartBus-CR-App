import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/config/api_config.dart';
import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/smartbus_header.dart';
import '../trip_tracking/services/trip_location_sender.dart';

/// Driver screen for an active trip (issue-4).
///
/// "Iniciar recorrido" starts sending the bus GPS location to the backend every
/// few seconds; "Terminar recorrido" stops it. All the logic lives in
/// [TripLocationSender]; this screen only renders its
/// [TripLocationSender.snapshot].
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, this.tripId, this.autoStart = false});

  /// UUID of the active trip. Passed in once the trip-selection flow exists; for
  /// now it falls back to [_demoTripId] so the screen is testable end to end.
  final String? tripId;

  /// When `true`, the trip GPS transmission starts as soon as the screen opens
  /// (the driver tapped "Iniciar recorrido" on the home tab). Otherwise the
  /// screen shows the idle state with its own "Iniciar recorrido" button.
  final bool autoStart;

  // TODO: recibir el viaje activo desde la pantalla de rutas cuando exista
  //       (Navigator.pushNamed(context, '/driver/trip', arguments: tripId)).
  //
  // Demo trip: must be the UUID of an `in_progress` trip of the backend DB
  // (the GPS service answers 409 to any other status; the trip is started by
  // the Dashboard). The driver must be the one assigned to it (403 otherwise).
  // Override it without touching code:
  //   flutter run --dart-define=DEMO_TRIP_ID=<trip-uuid>
  static const String _demoTripId = String.fromEnvironment(
    'DEMO_TRIP_ID',
    defaultValue: '01a09332-3457-7315-885e-4ebb218f7262',
  );

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final TripLocationSender _sender = TripLocationSender(
    interval: Duration(seconds: ApiConfig.gpsIntervalSeconds),
  );
  Timer? _ticker; // rebuilds every second so "hace Ns" stays fresh

  String get _tripId => widget.tripId ?? TripScreen._demoTripId;

  @override
  void initState() {
    super.initState();
    _sender.snapshot.addListener(_onSnapshot);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sender.start(tripId: _tripId);
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

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar recorrido'),
        content: const Text(
          '¿Seguro que quieres finalizar el recorrido? Se dejará de enviar la '
          'ubicación del autobús.',
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
    }
  }

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/driver/home');
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
          const SmartBusHeader(
            title: 'Recorrido',
            type: SmartBusUserType.driver,
          ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: SmartBusColors.blanco,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                    child: ValueListenableBuilder<TripTrackingSnapshot>(
                      valueListenable: _sender.snapshot,
                      builder: (context, snap, _) => _Body(
                        snap: snap,
                        onStart: () => _sender.start(tripId: _tripId),
                        onStop: _stop,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.snap,
    required this.onStart,
    required this.onStop,
  });

  final TripTrackingSnapshot snap;
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
      _ => _IdleView(snap: snap, onStart: onStart),
    };
  }
}

// ---------------------------------------------------------------------------

class _IdleView extends StatelessWidget {
  const _IdleView({required this.snap, required this.onStart});

  final TripTrackingSnapshot snap;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final starting = snap.state == TripTrackingState.starting;
    final stopped = snap.state == TripTrackingState.stopped;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          stopped ? Icons.check_circle_outline : Icons.navigation_outlined,
          size: 64,
          color: SmartBusColors.azulPrincipal.withValues(alpha: 0.35),
        ),
        const SizedBox(height: 16),
        Text(
          stopped ? 'Recorrido finalizado' : 'Listo para iniciar',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          stopped
              ? 'Se enviaron ${snap.sentCount} ubicaciones.'
              : 'Al iniciar, se enviará la ubicación del autobús cada pocos '
                    'segundos hasta que termines el recorrido.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        GradientButton(
          label: starting ? 'Solicitando permiso…' : 'Iniciar recorrido',
          icon: Icons.play_arrow_rounded,
          busy: starting,
          onPressed: starting ? null : onStart,
        ),
        if (snap.lastError != null && !starting) ...[
          const SizedBox(height: 14),
          _ErrorLine(message: snap.lastError!),
        ],
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
