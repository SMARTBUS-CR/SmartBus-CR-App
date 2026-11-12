import 'dart:math' as math;

import '../models/operations_models.dart';

/// A route close to the passenger: its stop closest to them, the direction
/// (pattern) that stop belongs to, and how far it is.
class NearbyRoute {
  const NearbyRoute({
    required this.route,
    required this.pattern,
    required this.stop,
    required this.distanceMeters,
  });

  final TransitRoute route;
  final RoutePattern pattern;
  final PatternStop stop;
  final double distanceMeters;
}

/// Finds the routes with at least one stop within [radiusMeters] of the
/// passenger, **on the device**.
///
/// Pure Dart (no Flutter, no plugins), so it is unit-tested directly. The
/// input is what `OperationsService.routesWithPatterns()` returns: one request
/// with every route, pattern and stop. If the catalogue grows, the Dashboard
/// already filters by distance (`GET ops/stops?filter[near]=lat,lng,radius_m`);
/// only the input of this class would change.
class NearbyRoutesFilter {
  const NearbyRoutesFilter({this.radiusMeters = defaultRadiusMeters});

  /// How close (meters) a stop must be for its route to count as "nearby".
  static const double defaultRadiusMeters = 1000;

  final double radiusMeters;

  /// Routes with a stop within [radiusMeters] (the limit included), closest
  /// first. Stops without coordinates are ignored.
  List<NearbyRoute> apply({
    required double latitude,
    required double longitude,
    required Iterable<TransitRoute> routes,
  }) {
    final nearby = [
      for (final route in routes)
        if (closest(route, latitude: latitude, longitude: longitude)
            case final candidate? when candidate.distanceMeters <= radiusMeters)
          candidate,
    ];
    nearby.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return nearby;
  }

  /// The stop of [route] (in any of its patterns) closest to the point, with
  /// no radius limit. `null` when the route has no located stop.
  ///
  /// On a tie, the first pattern / first stop wins, so the result is stable.
  static NearbyRoute? closest(
    TransitRoute route, {
    required double latitude,
    required double longitude,
  }) {
    NearbyRoute? best;
    for (final pattern in route.patterns) {
      for (final stop in pattern.stops) {
        final location = stop.location;
        if (location == null) continue;
        final distance = haversineMeters(
          latitude,
          longitude,
          location.latitude,
          location.longitude,
        );
        if (best == null || distance < best.distanceMeters) {
          best = NearbyRoute(
            route: route,
            pattern: pattern,
            stop: stop,
            distanceMeters: distance,
          );
        }
      }
    }
    return best;
  }
}

/// Mean Earth radius (meters), as used by the haversine formula.
const double earthRadiusMeters = 6371008.8;

/// Great-circle distance in meters between two points (haversine formula).
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
}

/// "230 m" / "1,4 km" — how the passenger reads a distance.
String formatDistance(double meters) {
  final rounded = (meters / 10).round() * 10;
  if (rounded < 1000) return '$rounded m';
  final km = (meters / 1000).toStringAsFixed(1);
  return '${km.endsWith('.0') ? km.substring(0, km.length - 2) : km.replaceAll('.', ',')} km';
}
