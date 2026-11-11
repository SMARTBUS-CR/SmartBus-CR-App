import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/gps_fix.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/gps_location_service.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/live_trip_tracker.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/trip_live_feed.dart';

const _tripId = '01a09332-3457-7315-885e-4ebb218f7262';

/// Fake `GET /gps/trips/{id}/location`: answers [next] (or throws [error]).
class _FakeGps implements GpsLocationService {
  TripTracking next = _tracking();
  ApiException? error;
  int calls = 0;

  @override
  Future<TripTracking> latestForTrip(String tripId) async {
    calls++;
    if (error != null) throw error!;
    return next;
  }

  @override
  Future<String?> send(GpsFix fix) => throw UnimplementedError();

  @override
  Future<String> authorizeChannel({
    required String socketId,
    required String channelName,
  }) => throw UnimplementedError();
}

class _FakeFeed implements TripLiveFeed {
  final StreamController<BusLocationUpdate> _locations =
      StreamController.broadcast(sync: true);
  final StreamController<Object> _rejections = StreamController.broadcast(
    sync: true,
  );
  final ValueNotifier<bool> _connected = ValueNotifier(false);
  final List<String> followed = [];
  bool disposed = false;

  @override
  Stream<BusLocationUpdate> get locations => _locations.stream;

  @override
  ValueListenable<bool> get connected => _connected;

  @override
  Stream<Object> get rejections => _rejections.stream;

  @override
  void follow(String tripId) => followed.add(tripId);

  @override
  Future<void> dispose() async => disposed = true;

  set isConnected(bool value) => _connected.value = value;

  void push(BusPosition position, {String tripId = _tripId}) => _locations.add(
    BusLocationUpdate(tripId: tripId, busId: 'bus', position: position),
  );

  void reject() => _rejections.add(StateError('403'));
}

final _t0 = DateTime.utc(2026, 11, 9, 15);

BusPosition _at(int second, {double lat = 9.93}) => BusPosition(
  latitude: lat,
  longitude: -84.08,
  speedKmh: 40,
  recordedAt: _t0.add(Duration(seconds: second)),
);

TripTracking _tracking({
  TripStatus status = TripStatus.inProgress,
  BusPosition? position,
  int? age,
}) => TripTracking(
  tripId: _tripId,
  status: status,
  freshness: TrackingFreshness.live,
  position: position,
  ageSeconds: age,
);

void main() {
  late _FakeGps gps;
  late _FakeFeed feed;

  setUp(() {
    gps = _FakeGps();
    feed = _FakeFeed();
  });

  LiveTripTracker build(FakeAsync async, {TripLiveFeed? withFeed}) =>
      LiveTripTracker(
        tripId: _tripId,
        service: gps,
        feed: withFeed ?? feed,
        clock: () => _t0.add(async.elapsed),
      );

  test('opening mid-trip shows the current position, then subscribes', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 4);
      final tracker = build(async)..start();
      async.flushMicrotasks();

      final state = tracker.state.value;
      expect(state.phase, LiveTripPhase.tracking);
      expect(state.status, TripStatus.inProgress);
      expect(state.position!.latitude, 9.93);
      // Seen 4 s ago on this phone's clock (server age, no clock skew).
      expect(state.positionSeenAt, _t0.subtract(const Duration(seconds: 4)));
      expect(feed.followed, [_tripId]);
      tracker.dispose();
    });
  });

  test('each BusLocationUpdated moves the bus; older events are ignored', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 0);
      final tracker = build(async)..start();
      async.flushMicrotasks();

      feed.push(_at(10, lat: 9.94));
      expect(tracker.state.value.position!.latitude, 9.94);

      feed.push(_at(5, lat: 1)); // arrived late
      expect(tracker.state.value.position!.latitude, 9.94);

      feed.push(_at(10, lat: 2)); // same recorded_at: duplicate
      expect(tracker.state.value.position!.latitude, 9.94);

      feed.push(_at(20, lat: 9.95), tripId: 'other-trip');
      expect(tracker.state.value.position!.latitude, 9.94);
      tracker.dispose();
    });
  });

  test('freshness goes live -> stale -> no_signal when updates stop', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 0);
      final tracker = build(async)..start();
      async.flushMicrotasks();
      LiveTripState state() => tracker.state.value;
      DateTime now() => _t0.add(async.elapsed);

      expect(state().freshnessAt(now()), TrackingFreshness.live);
      async.elapse(const Duration(seconds: 31));
      expect(state().freshnessAt(now()), TrackingFreshness.stale);
      async.elapse(const Duration(minutes: 5));
      expect(state().freshnessAt(now()), TrackingFreshness.noSignal);
      tracker.dispose();
    });
  });

  test('a scheduled trip is not tracking yet; the first event starts it', () {
    fakeAsync((async) {
      gps.next = _tracking(status: TripStatus.scheduled);
      final tracker = build(async)..start();
      async.flushMicrotasks();

      expect(tracker.state.value.phase, LiveTripPhase.tracking);
      expect(
        tracker.state.value.freshnessAt(_t0),
        TrackingFreshness.notTracking,
      );

      feed.push(_at(1));
      expect(tracker.state.value.status, TripStatus.inProgress);
      expect(tracker.state.value.freshnessAt(_t0), TrackingFreshness.live);
      tracker.dispose();
    });
  });

  test('while live over the socket, it does not poll the backend', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 0);
      final tracker = build(async)..start();
      async.flushMicrotasks();
      feed.isConnected = true;

      for (var s = 5; s <= 60; s += 5) {
        async.elapse(const Duration(seconds: 5));
        feed.push(_at(s));
      }
      expect(gps.calls, 1); // only the initial GET
      tracker.dispose();
    });
  });

  test('updates stop -> it asks again and detects "trip finished"', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 0);
      final tracker = build(async)..start();
      async.flushMicrotasks();
      feed.isConnected = true;

      // The driver ends the trip: no more events, the Dashboard marks it completed.
      gps.next = _tracking(status: TripStatus.completed, position: _at(0));
      async.elapse(const Duration(seconds: 45));

      expect(tracker.state.value.phase, LiveTripPhase.finished);
      expect(tracker.state.value.status, TripStatus.completed);
      expect(feed.disposed, isTrue); // leaves the channel

      final calls = gps.calls;
      async.elapse(const Duration(minutes: 2));
      expect(gps.calls, calls); // nothing else to ask
      tracker.dispose();
    });
  });

  test('15 s without positions -> asks right away: finished in <= 20 s', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 0);
      final tracker = build(async)..start();
      async.flushMicrotasks();
      feed.isConnected = true;

      gps.next = _tracking(status: TripStatus.completed, position: _at(0));
      async.elapse(const Duration(seconds: 10));
      expect(gps.calls, 1); // 10 s of silence is still normal

      async.elapse(const Duration(seconds: 10));
      expect(gps.calls, 2);
      expect(tracker.state.value.phase, LiveTripPhase.finished);
      tracker.dispose();
    });
  });

  test('a silent bus is asked at most once every 15 s', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 0);
      final tracker = build(async)..start();
      async.flushMicrotasks();
      feed.isConnected = true;

      // Still in progress, no new positions (tunnel, weak signal…).
      async.elapse(const Duration(seconds: 60));
      // Initial GET + at 15, 30, 45 and 60 s.
      expect(gps.calls, 5);
      tracker.dispose();
    });
  });

  test('back after a connection drop -> asks for the position again', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 0);
      final tracker = build(async)..start();
      async.flushMicrotasks();
      feed.isConnected = true;
      expect(gps.calls, 1);

      feed.isConnected = false;
      expect(tracker.state.value.realtime, isFalse);
      gps.next = _tracking(position: _at(8, lat: 9.97), age: 1);
      feed.isConnected = true;
      async.flushMicrotasks();

      expect(gps.calls, 2);
      expect(tracker.state.value.position!.latitude, 9.97);
      tracker.dispose();
    });
  });

  test('without real time it polls the position periodically', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 0);
      final tracker = LiveTripTracker(
        tripId: _tripId,
        service: gps,
        clock: () => _t0.add(async.elapsed),
      )..start();
      async.flushMicrotasks();

      gps.next = _tracking(position: _at(15, lat: 9.99), age: 0);
      async.elapse(const Duration(seconds: 15));

      expect(gps.calls, 2);
      expect(tracker.state.value.position!.latitude, 9.99);
      tracker.dispose();
    });
  });

  test('channel refused -> checks the status (cancelled trip)', () {
    fakeAsync((async) {
      final tracker = build(async)..start();
      async.flushMicrotasks();

      gps.next = _tracking(status: TripStatus.cancelled);
      feed.reject();
      async.flushMicrotasks();

      expect(tracker.state.value.phase, LiveTripPhase.finished);
      expect(tracker.state.value.status, TripStatus.cancelled);
      tracker.dispose();
    });
  });

  test('a finished trip does not subscribe', () {
    fakeAsync((async) {
      gps.next = _tracking(status: TripStatus.completed);
      final tracker = build(async)..start();
      async.flushMicrotasks();

      expect(tracker.state.value.phase, LiveTripPhase.finished);
      expect(feed.followed, isEmpty);
      tracker.dispose();
    });
  });

  test('404 -> not found; network error -> failed, and retry works', () {
    fakeAsync((async) {
      gps.error = ApiException.fromStatus(404);
      final missing = build(async)..start();
      async.flushMicrotasks();
      expect(missing.state.value.phase, LiveTripPhase.notFound);
      missing.dispose();

      gps.error = ApiException.noConnection;
      final offline = build(async, withFeed: _FakeFeed())..start();
      async.flushMicrotasks();
      expect(offline.state.value.phase, LiveTripPhase.failed);
      expect(offline.state.value.error, 'Sin conexión a Internet.');

      gps.error = null;
      offline.start();
      async.flushMicrotasks();
      expect(offline.state.value.phase, LiveTripPhase.tracking);
      offline.dispose();
    });
  });

  test('a failed refresh keeps the last position', () {
    fakeAsync((async) {
      gps.next = _tracking(position: _at(0), age: 0);
      final tracker = build(async)..start();
      async.flushMicrotasks();

      gps.error = ApiException.noConnection;
      async.elapse(const Duration(seconds: 15));

      expect(tracker.state.value.phase, LiveTripPhase.tracking);
      expect(tracker.state.value.position!.latitude, 9.93);
      expect(tracker.state.value.error, 'Sin conexión a Internet.');
      tracker.dispose();
    });
  });
}
