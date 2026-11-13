import 'package:geolocator/geolocator.dart';

/// A single GPS reading of a trip, ready to be sent to the GPS microservice.
///
/// The GPS service (`POST {gateway}/gps/locations`) expects a **JSON:API**
/// document: `{ "data": { "type": "gps-locations", "attributes": {...} } }`.
class GpsFix {
  const GpsFix({
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.speedKmh,
    this.accuracyMeters,
    this.isFinal = false,
  });

  /// Last reading of the trip (sent right before "Finalizar recorrido"): the
  /// GPS service stores it as the trip's end. Only the first reading (start)
  /// and this one are stored; the others are only broadcast live.
  final bool isFinal;

  /// UUID of the trip this reading belongs to.
  final String tripId;

  final double latitude;
  final double longitude;

  /// Ground speed in km/h. `null` when the device could not determine it.
  final double? speedKmh;

  /// Accuracy radius (meters) reported by the device. `null` when unknown.
  final double? accuracyMeters;

  /// Moment of the fix, always in UTC.
  final DateTime recordedAt;

  /// Builds a fix from a `geolocator` [Position].
  ///
  /// `position.speed` is in **m/s** and can be negative when unavailable, so it
  /// is converted to km/h or dropped. `position.accuracy` is `0` or negative
  /// when the platform does not report it, so it is dropped too.
  factory GpsFix.fromPosition(Position position, {required String tripId}) {
    return GpsFix(
      tripId: tripId,
      latitude: position.latitude,
      longitude: position.longitude,
      speedKmh: position.speed >= 0 ? position.speed * 3.6 : null,
      accuracyMeters: position.accuracy > 0 ? position.accuracy : null,
      recordedAt: position.timestamp.toUtc(),
    );
  }

  /// JSON:API document for `POST /gps/locations`.
  Map<String, dynamic> toJsonApi() => {
    'data': {
      'type': 'gps-locations',
      'attributes': {
        'trip_id': tripId,
        'latitude': latitude,
        'longitude': longitude,
        if (speedKmh != null) 'speed_kmh': speedKmh,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
        'recorded_at': recordedAt.toIso8601String(),
        if (isFinal) 'final': true,
      },
    },
  };

  @override
  String toString() =>
      'GpsFix(trip $tripId, $latitude, $longitude @ ${recordedAt.toIso8601String()})';
}
