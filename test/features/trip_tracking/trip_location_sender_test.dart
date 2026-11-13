import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/gps_fix.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
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

  /// How long each send takes (a slow backend).
  Duration delay = Duration.zero;
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<String?> send(GpsFix fix) async {
    calls++;
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (failAlwaysWith != null) throw failAlwaysWith!;
      if (calls <= failFirst) throw failWith;
      sent.add(fix);
      return '${sent.length}';
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<TripTracking> latestForTrip(String tripId) =>
      throw UnimplementedError();

  @override
  Future<String> authorizeChannel({
    required String socketId,
    required String channelName,
  }) => throw UnimplementedError();
}

/// Fake device GPS.
class _FakeGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.always;
  Position? lastKnown = _position();

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  /// Fresh fix (`getCurrentPosition`); `null` = same as [lastKnown].
  Position? current;
  int currentCalls = 0;

  /// Positions pushed by the OS while tracking.
  final StreamController<Position> stream = StreamController.broadcast();

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => lastKnown;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    currentCalls++;
    final position = current ?? lastKnown;
    // What the plugin does when no fix arrives within `timeLimit`.
    if (position == null) throw TimeoutException('no fix');
    return position;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      stream.stream;
}

Position _position({
  double lat = 9.93,
  double lng = -84.08,
  double speed = 10,
  DateTime? at,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: at ?? DateTime.utc(2026, 9, 7, 12),
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

/// Trips are identified by UUID on the backend.
const _tripId = '01a09332-3457-7315-885e-4ebb218f7262';

void main() {
  late _FakeGpsService service;
  late _FakeGeolocator geo;

  const interval = Duration(seconds: 5);

  setUp(() {
    service = _FakeGpsService();
    geo = _FakeGeolocator();
    GeolocatorPlatform.instance = geo;
  });

  /// What the Authentication Service says about a `401` (true = expired).
  var sessionExpired = true;
  var sessionChecks = 0;

  TripLocationSender build() => TripLocationSender(
    service: service,
    interval: interval,
    sessionCheck: () async {
      sessionChecks++;
      return sessionExpired;
    },
  );

  setUp(() {
    sessionExpired = true;
    sessionChecks = 0;
  });

  test('401 but the token works (the Gateway was slow): keeps sending, '
      'does not sign out', () {
    fakeAsync((async) {
      sessionExpired = false;
      service.failAlwaysWith = ApiException.fromStatus(401);
      final sender = build();

      sender.start(tripId: _tripId);
      async.flushMicrotasks();

      expect(sender.snapshot.value.state, TripTrackingState.tracking);
      expect(sender.snapshot.value.sessionExpired, isFalse);
      expect(sender.snapshot.value.lastError, 'Verificando la sesión…');
      expect(sender.snapshot.value.pendingCount, 1);
      expect(sessionChecks, 1);

      // Still failing a few ticks later: not asked again within a minute.
      async.elapse(interval * 3);
      async.flushMicrotasks();
      expect(sessionChecks, 1);

      // The GPS service recovers: sending goes on.
      service.failAlwaysWith = null;
      async.elapse(interval);
      async.flushMicrotasks();
      expect(service.sent, isNotEmpty);
      expect(sender.snapshot.value.lastError, isNull);
      sender.dispose();
    });
  });

  test('does not send when the location permission is denied', () {
    fakeAsync((async) {
      geo.permission = LocationPermission.denied;
      final sender = build();

      sender.start(tripId: _tripId);
      async.flushMicrotasks();

      expect(sender.snapshot.value.state, TripTrackingState.permissionDenied);
      async.elapse(interval * 3);
      async.flushMicrotasks();
      expect(service.sent, isEmpty);

      sender.dispose();
    });
  });

  test('a new start begins with fresh counters (shared sender)', () {
    fakeAsync((async) {
      final sender = build();
      sender.start(tripId: 'first-trip');
      async.flushMicrotasks();
      async.elapse(interval * 2);
      async.flushMicrotasks();
      expect(sender.snapshot.value.sentCount, greaterThan(0));

      sender.stop();
      sender.start(tripId: _tripId);
      async.flushMicrotasks();

      final snap = sender.snapshot.value;
      expect(snap.tripId, _tripId);
      expect(snap.sentCount, 1); // only the first fix of the new trip
      expect(service.sent.last.tripId, _tripId);
      sender.dispose();
    });
  });

  test('does not send when device location services are off', () {
    fakeAsync((async) {
      geo.serviceEnabled = false;
      final sender = build();

      sender.start(tripId: _tripId);
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

      sender.start(tripId: _tripId);
      async.flushMicrotasks(); // completes start() -> tracking + first tick

      expect(sender.snapshot.value.state, TripTrackingState.tracking);

      async.elapse(interval * 3);
      async.flushMicrotasks();

      // first immediate tick + 3 timer ticks
      expect(service.sent.length, greaterThanOrEqualTo(3));
      final fix = service.sent.first;
      expect(fix.tripId, _tripId);
      expect(fix.toJsonApi()['data']['attributes']['trip_id'], _tripId);
      expect(fix.latitude, 9.93);
      expect(fix.longitude, -84.08);
      expect(fix.speedKmh, closeTo(36, 0.001)); // 10 m/s -> 36 km/h
      expect(fix.accuracyMeters, 5);
      expect(fix.toJsonApi()['data']['attributes']['accuracy_meters'], 5);
      expect(fix.recordedAt.isUtc, isTrue);
      expect(sender.snapshot.value.sentCount, service.sent.length);

      sender.dispose();
    });
  });

  test('retries network failures: sending resumes once it recovers', () {
    fakeAsync((async) {
      service.failFirst = 2; // first 2 sends fail with "no connection"
      final sender = build();

      sender.start(tripId: _tripId);
      async.flushMicrotasks();
      async.elapse(interval * 3);
      async.flushMicrotasks();

      expect(service.sent, isNotEmpty);
      expect(sender.snapshot.value.pendingCount, 0);
      expect(sender.snapshot.value.lastError, isNull);

      sender.dispose();
    });
  });

  test('while offline only the newest reading waits (no backlog)', () {
    fakeAsync((async) {
      service.failAlwaysWith = ApiException.noConnection;
      final sender = build();

      sender.start(tripId: _tripId);
      async.flushMicrotasks();
      async.elapse(interval * 10);
      async.flushMicrotasks();

      expect(service.sent, isEmpty);
      expect(sender.snapshot.value.pendingCount, 1);
      expect(sender.snapshot.value.lastError, isNotNull);

      // Back online: one send, the newest reading, not ten old ones.
      service.failAlwaysWith = null;
      geo.lastKnown = _position(lat: 9.99);
      async.elapse(interval);
      async.flushMicrotasks();
      expect(service.sent, hasLength(1));
      expect(service.sent.single.latitude, 9.99);
      expect(sender.snapshot.value.pendingCount, 0);

      sender.dispose();
    });
  });

  test('a slow backend never builds a queue: the newest reading goes next', () {
    fakeAsync((async) {
      // Each send takes 12 s (more than two intervals).
      service.delay = const Duration(seconds: 12);
      final sender = build();

      sender.start(tripId: _tripId);
      async.flushMicrotasks();
      // A new position every 5 s (each one a later fix).
      for (var i = 1; i <= 4; i++) {
        geo.lastKnown = _position(
          lat: 9.93 + i / 1000,
          at: DateTime.utc(2026, 9, 7, 12, 0, i * 5),
        );
        async.elapse(interval);
        async.flushMicrotasks();
      }
      // t = 20 s → 36 s: the second send ends at 24 s, the third at 36 s.
      async.elapse(const Duration(seconds: 16));
      async.flushMicrotasks();

      // The readings that arrived while busy are not sent late: after each
      // send, the newest one goes (9.932, then 9.934), never 9.931 / 9.933.
      expect(service.sent.map((f) => f.latitude), [9.93, 9.932, 9.934]);
      expect(service.maxInFlight, 1);
      expect(sender.snapshot.value.pendingCount, lessThanOrEqualTo(1));

      sender.dispose();
    });
  });

  group('first reading (stored as the start of the trip)', () {
    test('a recent last known position is sent right away', () {
      fakeAsync((async) {
        geo.lastKnown = _position(lat: 9.95, at: DateTime.now());
        final sender = build();
        sender.start(tripId: _tripId);
        async.flushMicrotasks();

        expect(service.sent.first.latitude, 9.95);
        expect(geo.currentCalls, 0);
        sender.dispose();
      });
    });

    test('an old last known position is NOT used: a fresh fix is', () {
      fakeAsync((async) {
        // From another place, hours ago.
        geo.lastKnown = _position(lat: 10.5, at: DateTime.utc(2026, 9, 1));
        geo.current = _position(lat: 9.95, at: DateTime.now());
        final sender = build();
        sender.start(tripId: _tripId);
        async.flushMicrotasks();

        expect(geo.currentCalls, 1);
        expect(service.sent.first.latitude, 9.95);
        expect(service.sent.any((f) => f.latitude == 10.5), isFalse);
        sender.dispose();
      });
    });

    test('no position at all yet: nothing sent, and it keeps trying', () {
      fakeAsync((async) {
        geo.lastKnown = null;
        final sender = build();
        sender.start(tripId: _tripId);
        async.flushMicrotasks();
        expect(service.sent, isEmpty);
        expect(sender.snapshot.value.isTracking, isTrue);

        // The OS delivers one: sent at once.
        geo.stream.add(_position(lat: 9.96, at: DateTime.now()));
        async.flushMicrotasks();
        expect(service.sent.single.latitude, 9.96);
        sender.dispose();
      });
    });
  });

  test('a new position from the OS is sent at once, not on the next tick', () {
    fakeAsync((async) {
      final sender = build();
      sender.start(tripId: _tripId);
      async.flushMicrotasks();
      final before = service.sent.length;

      async.elapse(const Duration(seconds: 1)); // mid-interval
      geo.stream.add(
        _position(lat: 9.97, at: DateTime.utc(2026, 9, 7, 12, 0, 1)),
      );
      async.flushMicrotasks();

      expect(service.sent, hasLength(before + 1));
      expect(service.sent.last.latitude, 9.97);
      expect(sender.snapshot.value.latitude, 9.97); // the driver's map too

      // The next tick does not send it again (the bus is moving).
      async.elapse(interval);
      async.flushMicrotasks();
      expect(service.sent, hasLength(before + 1));
      sender.dispose();
    });
  });

  test('a stopped bus (same reading again) is re-stamped, so it is not '
      'ignored as a duplicate', () {
    fakeAsync((async) {
      final sender = build();
      sender.start(tripId: _tripId);
      async.flushMicrotasks();
      async.elapse(interval * 2);
      async.flushMicrotasks();

      final times = service.sent.map((f) => f.recordedAt).toList();
      expect(times.length, greaterThanOrEqualTo(3));
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isAfter(times[i - 1]), isTrue);
      }
      expect(service.sent.every((f) => f.latitude == 9.93), isTrue);
      sender.dispose();
    });
  });

  test('sendFinal: the current position marked final, newer than the last '
      'one sent', () {
    fakeAsync((async) {
      final sender = build();
      sender.start(tripId: _tripId);
      async.flushMicrotasks();
      final lastSent = service.sent.last.recordedAt;

      sender.sendFinal();
      async.flushMicrotasks();

      final fix = service.sent.last;
      expect(fix.isFinal, isTrue);
      expect(fix.toJsonApi()['data']['attributes']['final'], isTrue);
      expect(fix.latitude, 9.93);
      expect(fix.recordedAt.isAfter(lastSent), isTrue);
      // Regular readings do not carry the flag.
      expect(
        (service.sent.first.toJsonApi()['data']['attributes'] as Map)
            .containsKey('final'),
        isFalse,
      );
      sender.dispose();
    });
  });

  test('sendFinal does nothing when not tracking, and ignores failures', () {
    fakeAsync((async) {
      final sender = build();
      sender.sendFinal();
      async.flushMicrotasks();
      expect(service.calls, 0);

      sender.start(tripId: _tripId);
      async.flushMicrotasks();
      service.failAlwaysWith = ApiException.noConnection;
      var done = false;
      sender.sendFinal().then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isTrue);
      sender.dispose();
    });
  });

  test(
    'does NOT retry 4xx errors: the fix is dropped, the queue stays empty',
    () {
      fakeAsync((async) {
        service.failAlwaysWith = const ApiException(
          ApiErrorType.validation,
          'Datos inválidos.',
        );
        final sender = build();

        sender.start(tripId: _tripId);
        async.flushMicrotasks();
        async.elapse(interval * 3);
        async.flushMicrotasks();

        expect(service.sent, isEmpty);
        expect(sender.snapshot.value.pendingCount, 0); // dropped, not retried
        expect(sender.snapshot.value.lastError, 'Datos inválidos.');

        sender.dispose();
      });
    },
  );

  test('omits accuracy_meters when the device does not report it', () {
    final fix = GpsFix.fromPosition(
      Position(
        latitude: 9.93,
        longitude: -84.08,
        timestamp: DateTime.utc(2026, 9, 7, 12),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: -1,
        speedAccuracy: 0,
      ),
      tripId: _tripId,
    );

    final attributes = fix.toJsonApi()['data']['attributes'] as Map;
    expect(attributes.containsKey('accuracy_meters'), isFalse);
    expect(attributes.containsKey('speed_kmh'), isFalse);
  });

  final rejections = {
    409: 'El viaje no está en curso: todavía no se ha iniciado o ya terminó.',
    403: 'No eres el conductor asignado a este viaje.',
    404: 'No se encontró el viaje.',
    401: 'Tu sesión expiró. Inicia sesión nuevamente.',
  };
  rejections.forEach((status, message) {
    test('$status stops the transmission with a clear message', () {
      fakeAsync((async) {
        service.failAlwaysWith = ApiException.fromStatus(status);
        final sender = build();

        sender.start(tripId: _tripId);
        async.flushMicrotasks();

        expect(sender.snapshot.value.state, TripTrackingState.rejected);
        expect(sender.snapshot.value.lastError, message);
        expect(sender.snapshot.value.pendingCount, 0);
        // Only 401 means "go to login" (retrying would get 401 again).
        expect(sender.snapshot.value.sessionExpired, status == 401);

        // It does not keep failing every interval.
        final calls = service.calls;
        async.elapse(interval * 3);
        async.flushMicrotasks();
        expect(service.calls, calls);

        // "Reintentar" starts again once the problem is fixed.
        service.failAlwaysWith = null;
        sender.start(tripId: _tripId);
        async.flushMicrotasks();
        expect(sender.snapshot.value.state, TripTrackingState.tracking);
        expect(service.sent, isNotEmpty);

        sender.dispose();
      });
    });
  });

  test('stop() halts sending and clears the queue', () {
    fakeAsync((async) {
      service.failAlwaysWith = ApiException.noConnection; // build up a queue
      final sender = build();

      sender.start(tripId: _tripId);
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
