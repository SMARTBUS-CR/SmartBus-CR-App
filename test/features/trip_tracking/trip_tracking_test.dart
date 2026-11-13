import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';

const _tripId = '01a09332-3457-7315-885e-4ebb218f7262';

void main() {
  group('TripTracking.fromJsonApi (GET /gps/trips/{id}/location)', () {
    test('reads status, freshness, age and position', () {
      final tracking = TripTracking.fromJsonApi({
        'data': {
          'type': 'trip-trackings',
          'id': _tripId,
          'attributes': {
            'trip_id': _tripId,
            'status': 'in_progress',
            'freshness': 'live',
            'age_seconds': 4,
            'position': {
              'latitude': 9.93,
              'longitude': -84.08,
              'speed_kmh': 38.5,
              'accuracy_meters': 8.5,
              'recorded_at': '2026-11-09T15:00:00.000000Z',
            },
          },
        },
      });

      expect(tracking.tripId, _tripId);
      expect(tracking.status, TripStatus.inProgress);
      expect(tracking.freshness, TrackingFreshness.live);
      expect(tracking.ageSeconds, 4);
      expect(tracking.position!.latitude, 9.93);
      expect(tracking.position!.longitude, -84.08);
      expect(tracking.position!.speedKmh, 38.5);
      expect(tracking.position!.accuracyMeters, 8.5);
      expect(tracking.position!.recordedAt, DateTime.utc(2026, 11, 9, 15));
    });

    test('a trip without readings has no position', () {
      final tracking = TripTracking.fromJsonApi({
        'data': {
          'type': 'trip-trackings',
          'id': _tripId,
          'attributes': {
            'trip_id': _tripId,
            'status': 'scheduled',
            'freshness': 'not_tracking',
            'age_seconds': null,
            'position': null,
          },
        },
      });

      expect(tracking.status, TripStatus.scheduled);
      expect(tracking.freshness, TrackingFreshness.notTracking);
      expect(tracking.ageSeconds, isNull);
      expect(tracking.position, isNull);
    });

    test('unknown values do not break the app', () {
      final tracking = TripTracking.fromJsonApi({
        'data': {
          'id': _tripId,
          'attributes': {'status': 'paused', 'freshness': 'weird'},
        },
      });

      expect(tracking.tripId, _tripId);
      expect(tracking.status, TripStatus.unknown);
      expect(tracking.freshness, TrackingFreshness.noSignal);
    });

    test('a document without data is a FormatException', () {
      expect(
        () => TripTracking.fromJsonApi(const {}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('BusLocationUpdate reads the BusLocationUpdated payload', () {
    final update = BusLocationUpdate.fromJson({
      'id': null,
      'trip_id': _tripId,
      'bus_id': '01a09332-1111-7315-885e-4ebb218f7262',
      'latitude': 9.9367,
      'longitude': -84.1067,
      'speed_kmh': 44.1,
      'accuracy_meters': null,
      'recorded_at': '2026-09-03T18:00:00.000000Z',
    });

    expect(update.id, isNull);
    expect(update.tripId, _tripId);
    expect(update.position.latitude, 9.9367);
    expect(update.position.speedKmh, 44.1);
    expect(update.position.accuracyMeters, isNull);
  });

  test('freshness thresholds match the GPS service (30 s / 5 min)', () {
    expect(
      TrackingFreshness.forAge(const Duration(seconds: 30)),
      TrackingFreshness.live,
    );
    expect(
      TrackingFreshness.forAge(const Duration(seconds: 31)),
      TrackingFreshness.stale,
    );
    expect(
      TrackingFreshness.forAge(const Duration(seconds: 300)),
      TrackingFreshness.stale,
    );
    expect(
      TrackingFreshness.forAge(const Duration(seconds: 301)),
      TrackingFreshness.noSignal,
    );
  });
}
