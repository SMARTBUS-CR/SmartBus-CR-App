/// Status of a trip, as the Dashboard sets it (`trips.status`).
enum TripStatus {
  scheduled,
  inProgress,
  completed,
  cancelled,

  /// A value this version of the app does not know yet.
  unknown;

  static TripStatus fromApi(Object? value) => switch (value) {
    'scheduled' => TripStatus.scheduled,
    'in_progress' => TripStatus.inProgress,
    'completed' => TripStatus.completed,
    'cancelled' => TripStatus.cancelled,
    _ => TripStatus.unknown,
  };

  /// The trip will not move again: nothing else to follow.
  bool get isFinished =>
      this == TripStatus.completed || this == TripStatus.cancelled;
}

/// How recent the bus position is (same thresholds as the GPS service).
enum TrackingFreshness {
  /// Position from the last 30 s.
  live,

  /// Position from 30 s to 5 min ago (weak signal).
  stale,

  /// No position yet, or older than 5 min.
  noSignal,

  /// The trip is not running (scheduled, completed or cancelled).
  notTracking;

  static const liveSeconds = 30;
  static const staleSeconds = 300;

  static TrackingFreshness fromApi(Object? value) => switch (value) {
    'live' => TrackingFreshness.live,
    'stale' => TrackingFreshness.stale,
    'not_tracking' => TrackingFreshness.notTracking,
    _ => TrackingFreshness.noSignal,
  };

  /// Freshness of a position that is [age] old, for a trip in progress.
  static TrackingFreshness forAge(Duration age) {
    if (age.inSeconds <= liveSeconds) return TrackingFreshness.live;
    if (age.inSeconds <= staleSeconds) return TrackingFreshness.stale;
    return TrackingFreshness.noSignal;
  }
}

/// A position of the bus.
class BusPosition {
  const BusPosition({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.speedKmh,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double? speedKmh;
  final double? accuracyMeters;

  /// When the driver's phone took the reading (UTC). Used to order readings:
  /// a reading older than the one on the map is ignored.
  final DateTime recordedAt;

  /// Reads `latitude`, `longitude`, `speed_kmh`, `accuracy_meters`,
  /// `recorded_at` (same keys in the event and in the GET).
  factory BusPosition.fromJson(Map<String, dynamic> json) => BusPosition(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
    accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
    recordedAt: DateTime.parse(json['recorded_at'] as String).toUtc(),
  );

  bool isNewerThan(BusPosition? other) =>
      other == null || recordedAt.isAfter(other.recordedAt);
}

/// `BusLocationUpdated` event received on `private-trip.{tripId}`.
class BusLocationUpdate {
  const BusLocationUpdate({
    required this.tripId,
    required this.busId,
    required this.position,
    this.id,
  });

  /// Id of the stored reading; `null` when it was broadcast without storing.
  final String? id;
  final String tripId;
  final String busId;
  final BusPosition position;

  factory BusLocationUpdate.fromJson(Map<String, dynamic> json) =>
      BusLocationUpdate(
        id: json['id']?.toString(),
        tripId: json['trip_id'].toString(),
        busId: json['bus_id'].toString(),
        position: BusPosition.fromJson(json),
      );
}

/// `GET {gateway}/gps/trips/{tripId}/location` — `trip-trackings` resource:
/// the trip status, the bus's current position and how fresh it is.
class TripTracking {
  const TripTracking({
    required this.tripId,
    required this.status,
    required this.freshness,
    this.ageSeconds,
    this.position,
  });

  final String tripId;
  final TripStatus status;
  final TrackingFreshness freshness;

  /// Age of [position] in seconds, measured by the server. `null` without one.
  final int? ageSeconds;

  /// Last accepted position; `null` until the bus sends its first reading.
  final BusPosition? position;

  /// Parses the JSON:API document `{ "data": { "type": "trip-trackings", ... } }`.
  factory TripTracking.fromJsonApi(Map<String, dynamic> document) {
    final data = document['data'];
    if (data is! Map) {
      throw const FormatException('trip-trackings: missing "data".');
    }
    final attributes = data['attributes'];
    if (attributes is! Map) {
      throw const FormatException('trip-trackings: missing "attributes".');
    }
    final position = attributes['position'];
    return TripTracking(
      tripId: (attributes['trip_id'] ?? data['id']).toString(),
      status: TripStatus.fromApi(attributes['status']),
      freshness: TrackingFreshness.fromApi(attributes['freshness']),
      ageSeconds: (attributes['age_seconds'] as num?)?.toInt(),
      position: position is Map
          ? BusPosition.fromJson(Map<String, dynamic>.from(position))
          : null,
    );
  }
}
