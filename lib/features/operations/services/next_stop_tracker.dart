import 'dart:math' as math;

import '../models/operations_models.dart';
import 'nearby_routes_filter.dart';

/// Where the passenger should go to catch the bus: the stop closest to them
/// among the ones the bus has **not passed yet**.
class BoardingStop {
  const BoardingStop({
    required this.stop,
    required this.index,
    required this.walkMeters,
    this.stopsAway,
  });

  final PatternStop stop;

  /// Position of [stop] in [NextStopTracker.stops] (0 = first stop).
  final int index;

  /// Straight-line distance from the passenger to the stop.
  final double walkMeters;

  /// Stops the bus still has to reach before this one: 0 = this is the bus's
  /// next stop. `null` while the bus position is unknown.
  final int? stopsAway;

  /// Walking time at ~80 m per minute (at least 1 minute).
  int get walkMinutes => math.max(1, (walkMeters / 80).ceil());
}

/// The [BoardingStop] for a passenger at [latitude], [longitude]: the closest
/// stop the bus (per [tracker]) has not passed. `null` when the trip has no
/// stops or the bus already passed them all.
BoardingStop? boardingStopFor(
  NextStopTracker tracker,
  double latitude,
  double longitude,
) {
  final stops = tracker.stops;
  final busNext = tracker.nextIndex;
  final from = busNext ?? 0;
  BoardingStop? best;
  for (var i = from; i < stops.length; i++) {
    final location = stops[i].location!;
    final meters = haversineMeters(
      latitude,
      longitude,
      location.latitude,
      location.longitude,
    );
    if (best == null || meters < best.walkMeters) {
      best = BoardingStop(
        stop: stops[i],
        index: i,
        walkMeters: meters,
        stopsAway: busNext == null ? null : i - busNext,
      );
    }
  }
  return best;
}

/// Which stop of the trip comes next, from the bus GPS position. Used by the
/// driver ("Próxima parada") and the passenger (stops the bus has not passed).
///
/// Pure Dart (no Flutter) so it can be unit-tested.
///
/// - A stop counts as **passed** when the bus gets within [arrivalRadiusMeters]
///   of it. A stop the bus never got close to (wrong coordinates, a detour) is
///   skipped as soon as the bus reaches a later one.
/// - The **first** position (the trip may be resumed halfway) picks the
///   closest stop, and moves past it when the bus is already beyond it (closer
///   to the following stop than that stop is).
class NextStopTracker {
  NextStopTracker(List<PatternStop> stops, {this.arrivalRadiusMeters = 60})
    : stops = [
        for (final stop in stops)
          if (stop.location != null) stop,
      ];

  /// Stops with coordinates, in travel order.
  final List<PatternStop> stops;
  final double arrivalRadiusMeters;

  int? _next;

  /// Index in [stops] of the next stop; `null` before the first position,
  /// `stops.length` once the last stop was reached.
  int? get nextIndex => _next;

  /// The next stop, or `null` (no position yet, or the trip is at its end).
  PatternStop? get next {
    final index = _next;
    return index == null || index >= stops.length ? null : stops[index];
  }

  /// The bus reached the last stop.
  bool get finished => stops.isNotEmpty && _next == stops.length;

  /// Updates with a bus position. Returns `true` when the next stop changed.
  bool update(double latitude, double longitude) {
    if (stops.isEmpty) return false;
    final before = _next;
    double distanceTo(int index) {
      final location = stops[index].location!;
      return haversineMeters(
        latitude,
        longitude,
        location.latitude,
        location.longitude,
      );
    }

    var next = _next ?? _initialIndex(distanceTo);
    // Every stop reached (the next one, or a later one) is passed.
    for (var k = next; k < stops.length; k++) {
      if (distanceTo(k) <= arrivalRadiusMeters) next = k + 1;
    }
    _next = next;
    return before != _next;
  }

  /// Closest stop; the one after it when the bus is already past it.
  int _initialIndex(double Function(int index) distanceTo) {
    var closest = 0;
    var best = double.infinity;
    for (var i = 0; i < stops.length; i++) {
      final distance = distanceTo(i);
      if (distance < best) {
        best = distance;
        closest = i;
      }
    }
    if (closest + 1 >= stops.length) return closest;
    final a = stops[closest].location!;
    final b = stops[closest + 1].location!;
    final leg = haversineMeters(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
    // Closer to the following stop than the closest one is: already past it.
    return distanceTo(closest + 1) < leg ? closest + 1 : closest;
  }
}
