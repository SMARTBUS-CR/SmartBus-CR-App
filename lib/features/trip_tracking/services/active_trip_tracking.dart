import '../../../core/config/api_config.dart';
import 'trip_location_sender.dart';

/// The driver's GPS transmission for the **whole app session**, not owned by a
/// screen.
///
/// The driver tabs replace each other (`pushReplacementNamed`), so the
/// "Recorrido" screen is destroyed when the driver opens "Inicio" or "Mi
/// cuenta". If the screen owned the sender, the GPS would stop while the trip
/// is still `in_progress`, and the passengers would see the bus "sin señal".
/// Here it keeps sending until "Finalizar recorrido", logout or an expired
/// session ([stop]).
abstract final class ActiveTripTracking {
  static TripLocationSender? _sender;

  /// The shared sender (created on first use).
  static TripLocationSender get sender => _sender ??= TripLocationSender(
    interval: Duration(seconds: ApiConfig.gpsIntervalSeconds),
  );

  /// Stops sending (logout, session expired). No-op when nothing is running.
  static void stop() {
    final sender = _sender;
    if (sender != null && sender.snapshot.value.isTracking) sender.stop();
  }
}
