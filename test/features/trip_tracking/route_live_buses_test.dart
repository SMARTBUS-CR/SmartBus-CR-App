import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/route_live_buses.dart';

import '../operations/operations_fixtures.dart';
import 'trip_tracking_fakes.dart';

LiveBusTrip _trip(String id, {String unit = '12'}) => LiveBusTrip(
  id: id,
  status: TripStatus.inProgress,
  routePatternId: patternId,
  busUnit: unit,
);

void main() {
  late FakeOperations operations;
  late FakeGps gps;
  late FakeTrackers trackers;

  RouteLiveBuses build() => RouteLiveBuses(
    patternId: patternId,
    operations: operations,
    trackerFactory: trackers.call,
    refreshEvery: const Duration(seconds: 30),
  );

  setUp(() {
    operations = FakeOperations();
    gps = FakeGps();
    trackers = FakeTrackers(gps);
  });

  test('one tracker per bus running, with its position', () {
    fakeAsync((async) {
      operations.buses = {
        patternId: [_trip('t1'), _trip('t2', unit: '7')],
      };
      gps.trips
        ..['t1'] = inProgressAt('t1', 10.1, -84.1)
        ..['t2'] = inProgressAt('t2', 10.2, -84.2);

      final live = build()..start();
      async.flushMicrotasks();

      final state = live.state.value;
      expect(state.loading, isFalse);
      expect(operations.calls, ['buses $patternId']);
      expect(state.buses.map((b) => b.trip.id), ['t1', 't2']);
      expect(state.buses.first.state.position!.latitude, 10.1);
      expect(state.buses.last.trip.busLabel, 'Unidad 7');
      live.dispose();
    });
  });

  test('no buses running: empty, not loading', () {
    fakeAsync((async) {
      final live = build()..start();
      async.flushMicrotasks();

      expect(live.state.value.loading, isFalse);
      expect(live.state.value.buses, isEmpty);
      expect(trackers.built, isEmpty);
      live.dispose();
    });
  });

  test('asks the Dashboard again: new trips appear, gone ones leave', () {
    fakeAsync((async) {
      operations.buses = {
        patternId: [_trip('t1')],
      };
      gps.trips
        ..['t1'] = inProgressAt('t1', 10.1, -84.1)
        ..['t2'] = inProgressAt('t2', 10.2, -84.2);
      final live = build()..start();
      async.flushMicrotasks();
      expect(live.state.value.buses.map((b) => b.trip.id), ['t1']);

      // t1 finished, a driver started t2.
      operations.buses = {
        patternId: [_trip('t2')],
      };
      async.elapse(const Duration(seconds: 30));

      expect(live.state.value.buses.map((b) => b.trip.id), ['t2']);
      expect(trackers.built.map((t) => t.tripId), ['t1', 't2']);
      live.dispose();
    });
  });

  test('a trip the GPS service reports finished disappears right away', () {
    fakeAsync((async) {
      operations.buses = {
        patternId: [_trip('t1'), _trip('t2')],
      };
      gps.trips
        ..['t1'] = finishedTrip('t1')
        ..['t2'] = inProgressAt('t2', 10.2, -84.2);
      final live = build()..start();
      async.flushMicrotasks();

      expect(live.state.value.buses.map((b) => b.trip.id), ['t2']);
      live.dispose();
    });
  });

  test('the Dashboard fails: keeps the buses, reports the error', () {
    fakeAsync((async) {
      operations.buses = {
        patternId: [_trip('t1')],
      };
      gps.trips['t1'] = inProgressAt('t1', 10.1, -84.1);
      final live = build()..start();
      async.flushMicrotasks();

      final failing = _FailingOperations()..buses = operations.buses;
      final second = RouteLiveBuses(
        patternId: patternId,
        operations: failing,
        trackerFactory: trackers.call,
      )..start();
      async.flushMicrotasks();

      expect(second.state.value.loading, isFalse);
      expect(second.state.value.buses, isEmpty);
      expect(second.state.value.error, ApiException.noConnection.message);
      expect(live.state.value.buses, hasLength(1));
      live.dispose();
      second.dispose();
    });
  });

  test('dispose stops every tracker and the refresh', () {
    fakeAsync((async) {
      operations.buses = {
        patternId: [_trip('t1')],
      };
      gps.trips['t1'] = inProgressAt('t1', 10.1, -84.1);
      final live = build()..start();
      async.flushMicrotasks();

      live.dispose();
      operations.calls.clear();
      async.elapse(const Duration(minutes: 2));

      expect(operations.calls, isEmpty);
      expect(async.periodicTimerCount, 0);
    });
  });
}

class _FailingOperations extends FakeOperations {
  @override
  Future<List<LiveBusTrip>> ongoingTrips(String patternId) async =>
      throw ApiException.noConnection;
}
