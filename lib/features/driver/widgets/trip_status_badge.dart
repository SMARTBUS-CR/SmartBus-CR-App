import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../operations/models/operations_models.dart';
import '../../trip_tracking/models/trip_tracking.dart';
import '../../trip_tracking/services/trip_location_sender.dart';

/// Text and color of a trip status, shared by the driver screens (Inicio and
/// Recorrido show the same label and color).
(String, Color) tripStatusBadge(TripStatus status) => switch (status) {
  TripStatus.scheduled => ('Programado', SmartBusColors.azulPrincipal),
  TripStatus.inProgress => ('En curso', SmartBusColors.verdeMenta),
  TripStatus.completed => ('Finalizado', SmartBusColors.completado),
  TripStatus.cancelled => ('Cancelado', SmartBusColors.error),
  TripStatus.unknown => ('—', Colors.grey),
};

/// Icon of a trip status (the badge never relies on color alone).
IconData tripStatusIcon(TripStatus status) => switch (status) {
  TripStatus.scheduled => Icons.schedule,
  TripStatus.inProgress => Icons.directions_bus_filled,
  TripStatus.completed => Icons.check_circle_outline,
  TripStatus.cancelled => Icons.cancel_outlined,
  TripStatus.unknown => Icons.help_outline,
};

/// Whether the app is sending the location of a trip in progress.
enum TripGpsStatus {
  /// Sending (or about to send) the location of this trip.
  sending,

  /// Not sending: the driver left the screen, reopened the app, no
  /// permission, location off…
  stopped,

  /// The GPS service refused the location (403 / 409…).
  rejected;

  /// The sender state of [tripId], from [snap].
  static TripGpsStatus of(TripTrackingSnapshot snap, String tripId) {
    if (snap.tripId != tripId) return TripGpsStatus.stopped;
    return switch (snap.state) {
      TripTrackingState.tracking ||
      TripTrackingState.starting => TripGpsStatus.sending,
      TripTrackingState.rejected => TripGpsStatus.rejected,
      _ => TripGpsStatus.stopped,
    };
  }
}

/// What the driver sees about a trip: the Dashboard status combined with the
/// location sending of the app.
class TripStatusInfo {
  const TripStatusInfo({
    required this.label,
    required this.color,
    required this.icon,
    required this.message,
  });

  /// Combines [trip] (Dashboard) and [snap] (this phone's GPS). [now] is for
  /// the "hace Ns" of the last confirmed location.
  factory TripStatusInfo.of(
    DriverTrip trip,
    TripTrackingSnapshot snap, {
    DateTime? now,
  }) {
    final (label, color) = tripStatusBadge(trip.status);
    final icon = tripStatusIcon(trip.status);
    switch (trip.status) {
      case TripStatus.scheduled:
        return TripStatusInfo(
          label: label,
          color: color,
          icon: icon,
          message: 'Listo para iniciar',
        );
      case TripStatus.completed:
        final arrival = trip.actualArrivalAt;
        return TripStatusInfo(
          label: label,
          color: color,
          icon: icon,
          message: arrival == null
              ? 'Recorrido finalizado'
              : 'Recorrido finalizado · llegada ${formatHour(arrival)}',
        );
      case TripStatus.cancelled:
        return TripStatusInfo(
          label: label,
          color: color,
          icon: icon,
          message: 'Este viaje fue cancelado',
        );
      case TripStatus.unknown:
        return TripStatusInfo(
          label: label,
          color: color,
          icon: icon,
          message: 'Estado desconocido',
        );
      case TripStatus.inProgress:
        return switch (TripGpsStatus.of(snap, trip.id)) {
          TripGpsStatus.sending => TripStatusInfo(
            label: label,
            color: color,
            icon: Icons.gps_fixed,
            message: snap.state == TripTrackingState.starting
                ? 'Iniciando el envío de ubicación…'
                : 'Enviando ubicación · ${lastSentLabel(snap.lastSentAt, now)}',
          ),
          TripGpsStatus.stopped => const TripStatusInfo(
            label: 'En curso · ubicación detenida',
            color: SmartBusColors.retraso,
            icon: Icons.location_disabled,
            message: 'No se está enviando tu ubicación',
          ),
          TripGpsStatus.rejected => TripStatusInfo(
            label: 'En curso · ubicación rechazada',
            color: SmartBusColors.error,
            icon: Icons.gps_off,
            message: snap.lastError ?? 'El servidor rechazó la ubicación.',
          ),
        };
    }
  }

  final String label;
  final Color color;
  final IconData icon;
  final String message;

  /// "última hace 3 s", "última hace 2 min", "sin confirmar".
  static String lastSentLabel(DateTime? at, [DateTime? now]) {
    if (at == null) return 'sin confirmar';
    final secs = (now ?? DateTime.now()).difference(at).inSeconds;
    if (secs <= 1) return 'última hace un momento';
    if (secs < 60) return 'última hace $secs s';
    return 'última hace ${secs ~/ 60} min';
  }
}

/// Status pill: icon + text over a light tint of [color]. Screen readers
/// read "Estado del viaje: …".
class TripStatusBadge extends StatelessWidget {
  const TripStatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });

  /// The Dashboard status only (the Inicio list).
  factory TripStatusBadge.forStatus(TripStatus status, {Key? key}) {
    final (label, color) = tripStatusBadge(status);
    return TripStatusBadge(
      key: key,
      label: label,
      color: color,
      icon: tripStatusIcon(status),
    );
  }

  /// Status + location sending (the Recorrido screen).
  factory TripStatusBadge.forInfo(TripStatusInfo info, {Key? key}) =>
      TripStatusBadge(
        key: key,
        label: info.label,
        color: info.color,
        icon: info.icon,
      );

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Estado del viaje: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
