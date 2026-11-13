/// Whether a route **passes near** a point by its line on the road, not only
/// by its stops. Rural buses stop where a passenger waves on the road, and the
/// catalogue has few stops (mostly terminals), so this finds routes the stop
/// search misses. Computed on the phone with the catalogue already loaded
/// (`route_geometry` of each direction).
library;

import 'dart:math' as math;

import '../models/operations_models.dart';
import '../models/route_timetable.dart';
import 'nearby_routes_filter.dart' show haversineMeters;

/// The closest point of a line to a place.
class PathHit {
  const PathHit({
    required this.point,
    required this.distanceMeters,
    required this.alongMeters,
  });

  /// Where on the line (the road) the passenger should wait / get off.
  final GeoPoint point;

  /// From the place to [point] (straight line).
  final double distanceMeters;

  /// From the start of the line to [point], along it.
  final double alongMeters;
}

/// Closest point of [path] to ([latitude], [longitude]); `null` with fewer
/// than 2 points. Each segment is projected on a flat plane around the place
/// (accurate at walking distances).
PathHit? closestOnPath(List<GeoPoint> path, double latitude, double longitude) {
  if (path.length < 2) return null;
  // Meters per degree around the place (same Earth radius as the haversine
  // distances, so both agree).
  const mPerLat = 111195.0;
  final mPerLng = mPerLat * math.cos(latitude * math.pi / 180);
  double x(GeoPoint p) => (p.longitude - longitude) * mPerLng;
  double y(GeoPoint p) => (p.latitude - latitude) * mPerLat;

  PathHit? best;
  var along = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    final a = path[i];
    final b = path[i + 1];
    final ax = x(a), ay = y(a), bx = x(b), by = y(b);
    final dx = bx - ax, dy = by - ay;
    final lengthSq = dx * dx + dy * dy;
    // Position of the place's projection on the segment (0 = a, 1 = b).
    final t = lengthSq == 0
        ? 0.0
        : ((-ax * dx - ay * dy) / lengthSq).clamp(0.0, 1.0);
    final px = ax + t * dx, py = ay + t * dy;
    final distance = math.sqrt(px * px + py * py);
    final segment = haversineMeters(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
    if (best == null || distance < best.distanceMeters) {
      best = PathHit(
        point: GeoPoint(
          a.latitude + t * (b.latitude - a.latitude),
          a.longitude + t * (b.longitude - a.longitude),
        ),
        distanceMeters: distance,
        alongMeters: along + t * segment,
      );
    }
    along += segment;
  }
  return best;
}

/// Length of [path] in meters.
double pathLengthMeters(List<GeoPoint> path) {
  var total = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    total += haversineMeters(
      path[i].latitude,
      path[i].longitude,
      path[i + 1].latitude,
      path[i + 1].longitude,
    );
  }
  return total;
}

/// A direction whose line passes near the passenger (and, for a trip, near
/// the destination too, further along the line).
class PassingRoute {
  const PassingRoute({
    required this.route,
    required this.pattern,
    required this.origin,
    required this.lengthMeters,
    this.destination,
  });

  final TransitRoute route;
  final RoutePattern pattern;

  /// Where the line passes closest to the passenger.
  final PathHit origin;

  /// Where it passes closest to the destination (trips only).
  final PathHit? destination;

  /// Whole length of the line.
  final double lengthMeters;

  /// Minutes from the start of the direction to [origin] (approximate: by
  /// distance, with the direction's driving time); `null` without it.
  double? get minutesToOrigin => _minutesAt(origin.alongMeters);

  /// Minutes on the bus from [origin] to [destination] (approximate).
  double? get rideMinutes {
    final destination = this.destination;
    final start = minutesToOrigin;
    final end = destination == null
        ? null
        : _minutesAt(destination.alongMeters);
    return start == null || end == null ? null : end - start;
  }

  double? _minutesAt(double alongMeters) {
    final seconds = pattern.drivingDurationSeconds;
    if (seconds == null || lengthMeters <= 0) return null;
    return alongMeters / lengthMeters * seconds / 60;
  }

  /// When the bus would pass by [origin] next (approximate): the next
  /// departure of [weekly] (today or tomorrow) plus [minutesToOrigin].
  /// `null` without a timetable or driving time.
  DateTime? nextPassAt(List<RouteSchedule> weekly, DateTime now) {
    final offset = minutesToOrigin;
    if (offset == null) return null;
    final delay = Duration(seconds: (offset * 60).round());
    for (var day = 0; day <= 1; day++) {
      final date = DateTime(now.year, now.month, now.day + day);
      for (final departure in departuresOn(weekly, date)) {
        final passes = DateTime(
          date.year,
          date.month,
          date.day,
          departure.hour,
          departure.minute,
        ).add(delay);
        if (!passes.isBefore(now)) return passes;
      }
    }
    return null;
  }
}

/// Directions whose line passes within [radiusMeters] of the passenger,
/// closest first (one per direction).
List<PassingRoute> routesPassingNear({
  required double latitude,
  required double longitude,
  required List<TransitRoute> routes,
  double radiusMeters = 1000,
  int limit = 10,
}) {
  final found = <PassingRoute>[
    for (final route in routes)
      for (final pattern in route.patterns)
        if (pattern.hasGeometry)
          if (closestOnPath(pattern.path, latitude, longitude) case final hit?
              when hit.distanceMeters <= radiusMeters)
            PassingRoute(
              route: route,
              pattern: pattern,
              origin: hit,
              lengthMeters: pathLengthMeters(pattern.path),
            ),
  ]..sort((a, b) => a.origin.distanceMeters.compareTo(b.origin.distanceMeters));
  return found.take(limit).toList();
}

/// Directions whose line passes within [radiusMeters] of the origin **and**,
/// further along, of the destination: the bus can take the passenger there
/// without a stop nearby. Least walking first.
List<PassingRoute> routesPassingBetween({
  required GeoPoint origin,
  required GeoPoint destination,
  required List<TransitRoute> routes,
  double radiusMeters = 1000,
  int limit = 5,
}) {
  final found = <PassingRoute>[];
  for (final route in routes) {
    for (final pattern in route.patterns) {
      if (!pattern.hasGeometry) continue;
      final from = closestOnPath(
        pattern.path,
        origin.latitude,
        origin.longitude,
      );
      final to = closestOnPath(
        pattern.path,
        destination.latitude,
        destination.longitude,
      );
      if (from == null || to == null) continue;
      if (from.distanceMeters > radiusMeters ||
          to.distanceMeters > radiusMeters) {
        continue;
      }
      // The bus must reach the origin first (its direction of travel).
      if (to.alongMeters <= from.alongMeters) continue;
      found.add(
        PassingRoute(
          route: route,
          pattern: pattern,
          origin: from,
          destination: to,
          lengthMeters: pathLengthMeters(pattern.path),
        ),
      );
    }
  }
  double walk(PassingRoute r) =>
      r.origin.distanceMeters + r.destination!.distanceMeters;
  found.sort((a, b) => walk(a).compareTo(walk(b)));
  return found.take(limit).toList();
}
