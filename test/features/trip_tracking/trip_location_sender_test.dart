import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/gps_fix.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/gps_location_service.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/trip_location_sender.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Fake backend: records every fix, or fails a configurable number of times.
class _FakeGpsService implements GpsLocationService {
  final List<GpsFix> sent = [];

  /// Fail the first N calls to [send] (0 = never fail).
  int failFirst = 0;

  /// Fail *every* call to [send] with this exception (overrides [failFirst]).
  ApiException? failAlwaysWith;

  ApiException failWith = ApiException.noConnection;
  int calls = 0;

  @override
  Future<String?> send(GpsFix fix) async {
    calls++;
    if (failAlwaysWith != null) throw failAlwaysWith!;
    if (calls <= failFirst) throw failWith;
    sent.add(fix);
    return '${sent.length}';
  }

  @override
  Future<Map<String, dynamic>> latestForTrip(int tripId) async => const {};
}

/// Fake device GPS.
class _FakeGeolocator extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.always;
  Position? lastKnown = _position();

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async =>
      lastKnown;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream<Position>.empty();
}

Position _position({double lat = 9.93, double lng = -84.08, double speed = 10}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.utc(2026, 9, 7, 12),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}

// ---------------------------------------------------------------------------

void main() {
  late _FakeGpsService service;
  late _FakeGeolocator geo;

  const interval = Duration(seconds: 5);

  setUp(() {
    service = _FakeGpsService();
    geo = _FakeGeolocator();
    GeolocatorPlatform.instance = geo;
  });

  TripLocationSender build() =>
      TripLocationSender(service: service, interval: interval);

  test('does not send when the location permission is denied', () {
    fakeAsync((async) {
      geo.permission = LocationPermission.denied;
      final sender = build();

      sender.start(tripId: 25);
      async.flushMicrotasks();

      expect(sender.snapshot.value.state, TripTrackingState.permissionDenied);
      async.elapse(interval * 3);
      async.flushMicrotasks();
      expect(service.sent, isEmpty);

      sender.dispose();
    });
  });

  test('does not send when device location services are off', () {
    fakeAsync((async) {
      geo.serviceEnabled = false;
      final sender = build();

      sender.start(tripId: 25);
      async.flushMicrotasks();

      expect(
        sender.snapshot.value.state,
        TripTrackingState.locationServicesDisabled,
      );
      sender.dispose();
    });
  });

  test('sends the trip location once per interval with the right payload', () {
    fakeAsync((async) {
      final sender = build();

      sender.start(tripId: 25);
      async.flushMicrotasks(); // completes start() -> tracking + first tick

      expect(sender.snapshot.value.state, TripTrackingState.tracking);

      async.elapse(interval * 3);
      async.flushMicrotasks();

      // first immediate tick + 3 timer ticks
      expect(service.sent.length, greaterThanOrEqualTo(3));
      final fix = service.sent.first;
      expect(fix.tripId, 25);
      expect(fix.latitude, 9.93);
      expect(fix.longitude, -84.08);
      expect(fix.speedKmh, closeTo(36, 0.001)); // 10 m/s -> 36 km/h
      expect(fix.recordedAt.isUtc, isTrue);
      expect(sender.snapshot.value.sentCount, service.sent.length);

      sender.dispose();
    });
  });

  test('retries network failures: queued fixes are all sent once it recovers',
      () {
    fakeAsync((async) {
      service.failFirst = 2; // first 2 sends fail with "no connection"
      final sender = build();

      sender.start(tripId: 25);
      async.flushMicrotasks();
      async.elapse(interval * 3);
      async.flushMicrotasks();

      // Nothing lost: the fixes that failed were retried and eventually stored.
      expect(service.sent.length, greaterThanOrEqualTo(3));
      expect(sender.snapshot.value.pendingCount, 0);

      sender.dispose();
    });
  });

  test('keeps fixes queued while offline (retryable errors grow the queue)', () {
    fakeAsync((async) {
      service.failAlwaysWith = ApiException.noConnection;
      final sender = build();

      sender.start(tripId: 25);
      async.flushMicrotasks();
      async.elapse(interval * 3);
      async.flushMicrotasks();

      expect(service.sent, isEmpty);
      expect(sender.snapshot.value.pendingCount, greaterThan(0));
      expect(sender.snapshot.value.lastError, isNotNull);

      sender.dispose();
    });
  });

  test('does NOT retry 4xx errors: the fix is dropped, the queue stays empty',
      () {
    fakeAsync((async) {
      service.failAlwaysWith =
          const ApiException(ApiErrorType.validation, 'Datos inválidos.');
      final sender = build();

      sender.start(tripId: 25);
      async.flushMicrotasks();
      async.elapse(interval * 3);
      async.flushMicrotasks();

      expect(service.sent, isEmpty);
      expect(sender.snapshot.value.pendingCount, 0); // dropped, not retried
      expect(sender.snapshot.value.lastError, 'Datos inválidos.');

      sender.dispose();
    });
  });

  test('stop() halts sending and clears the queue', () {
    fakeAsync((async) {
      service.failAlwaysWith = ApiException.noConnection; // build up a queue
      final sender = build();

      sender.start(tripId: 25);
      async.flushMicrotasks();
      async.elapse(interval * 2);
      async.flushMicrotasks();
      expect(sender.snapshot.value.pendingCount, greaterThan(0));

      sender.stop();
      async.flushMicrotasks();

      expect(sender.snapshot.value.state, TripTrackingState.stopped);
      expect(sender.snapshot.value.pendingCount, 0);

      final callsAfterStop = service.calls;
      async.elapse(interval * 3);
      async.flushMicrotasks();
      expect(service.calls, callsAfterStop); // no more attempts

      sender.dispose();
    });
  });
}
