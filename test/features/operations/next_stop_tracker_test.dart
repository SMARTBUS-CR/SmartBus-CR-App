import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/operations/services/next_stop_tracker.dart';

import 'operations_fixtures.dart';

void main() {
  // Three stops ~1.1 km apart along a meridian.
  final stops = [
    stopAt('Terminal', 10.460, -84.0, seq: 1),
    stopAt('Centro', 10.470, -84.0, seq: 2),
    stopAt('Muelle', 10.480, -84.0, seq: 3),
  ];

  test('no position yet: no next stop', () {
    final tracker = NextStopTracker(stops);
    expect(tracker.nextIndex, isNull);
    expect(tracker.next, isNull);
    expect(tracker.finished, isFalse);
  });

  test('at the terminal: the next stop is the second one', () {
    final tracker = NextStopTracker(stops);
    expect(tracker.update(10.4601, -84.0), isTrue);
    expect(tracker.next?.name, 'Centro');
  });

  test('before the terminal: the first stop is next', () {
    final tracker = NextStopTracker(stops);
    tracker.update(10.455, -84.0); // ~550 m before it
    expect(tracker.next?.name, 'Terminal');
  });

  test('advances when the bus reaches each stop, then finishes', () {
    final tracker = NextStopTracker(stops)..update(10.4601, -84.0);

    expect(tracker.update(10.465, -84.0), isFalse); // halfway, no change
    expect(tracker.next?.name, 'Centro');

    expect(tracker.update(10.4702, -84.0), isTrue);
    expect(tracker.next?.name, 'Muelle');

    tracker.update(10.4800, -84.0);
    expect(tracker.finished, isTrue);
    expect(tracker.next, isNull);
  });

  test('resumed halfway: past the closest stop, the following is next', () {
    final tracker = NextStopTracker(stops);
    tracker.update(10.4730, -84.0); // just after "Centro"
    expect(tracker.next?.name, 'Muelle');
  });

  test('a stop never reached is skipped when a later one is reached', () {
    final tracker = NextStopTracker(stops)..update(10.4601, -84.0);
    tracker.update(10.4800, -84.0); // straight to "Muelle"
    expect(tracker.finished, isTrue);
  });

  test('stops without coordinates are ignored', () {
    final tracker = NextStopTracker([
      const PatternStop(stopId: 'x', name: 'Sin coordenadas', sequence: 0),
      ...stops,
    ]);
    expect(tracker.stops.map((s) => s.name), ['Terminal', 'Centro', 'Muelle']);
  });

  group('boardingStopFor (where the passenger should go)', () {
    test('the closest stop the bus has not passed', () {
      // Bus at the terminal (next: Centro); passenger near the terminal.
      final tracker = NextStopTracker(stops)..update(10.4601, -84.0);
      final boarding = boardingStopFor(tracker, 10.461, -84.0)!;

      // The terminal is closer, but the bus already left it.
      expect(boarding.stop.name, 'Centro');
      expect(boarding.stopsAway, 0); // the bus's next stop
      expect(boarding.walkMeters, closeTo(1000, 20));
      expect(boarding.walkMinutes, 13); // ~80 m per minute
    });

    test('a later stop: how many stops the bus still has to reach', () {
      final tracker = NextStopTracker(stops)..update(10.4601, -84.0);
      final boarding = boardingStopFor(tracker, 10.4805, -84.0)!;

      expect(boarding.stop.name, 'Muelle');
      expect(boarding.stopsAway, 1);
      expect(boarding.walkMinutes, 1);
    });

    test('bus position unknown: any stop, without "stops away"', () {
      final boarding = boardingStopFor(NextStopTracker(stops), 10.4601, -84.0)!;
      expect(boarding.stop.name, 'Terminal');
      expect(boarding.stopsAway, isNull);
    });

    test('the bus passed every stop: none', () {
      final tracker = NextStopTracker(stops)
        ..update(10.4601, -84.0)
        ..update(10.4800, -84.0);
      expect(boardingStopFor(tracker, 10.47, -84.0), isNull);
    });
  });

  test('no stops: never changes', () {
    final tracker = NextStopTracker(const []);
    expect(tracker.update(10.46, -84.0), isFalse);
    expect(tracker.finished, isFalse);
  });
}
