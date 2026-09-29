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
  });

  /// UUID of the trip this reading belongs to.
  final String tripId;

  final double latitude;
  final double longitude;

  /// Ground speed in km/h. `null` when the device could not determine it.
  final double? speedKmh;

  /// Moment of the fix, always in UTC.
  final DateTime recordedAt;

  /// Builds a fix from a `geolocator` [Position].
  ///
  /// `position.speed` is in **m/s** and can be negative when unavailable, so it
  /// is converted to km/h or dropped.
  factory GpsFix.fromPosition(Position position, {required String tripId}) {
    return GpsFix(
      tripId: tripId,
      latitude: position.latitude,
      longitude: position.longitude,
      speedKmh: position.speed >= 0 ? position.speed * 3.6 : null,
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
            'recorded_at': recordedAt.toIso8601String(),
          },
        },
      };

  @override
  String toString() =>
      'GpsFix(trip $tripId, $latitude, $longitude @ ${recordedAt.toIso8601String()})';
}
