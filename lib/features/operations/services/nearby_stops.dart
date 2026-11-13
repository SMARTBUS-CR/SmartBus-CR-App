import '../models/operations_models.dart';
import 'nearby_routes_filter.dart';

/// A route direction that stops at a [NearbyStop].
class StopRoute {
  const StopRoute({required this.route, required this.pattern});

  final TransitRoute route;
  final RoutePattern pattern;
}

/// A stop near the passenger, with every route direction that stops there.
class NearbyStop {
  const NearbyStop({
    required this.stopId,
    required this.name,
    required this.location,
    required this.distanceMeters,
    required this.routes,
  });

  final String stopId;
  final String name;
  final GeoPoint location;

  /// Straight-line distance from the passenger.
  final double distanceMeters;

  /// Route directions that stop here, by route code.
  final List<StopRoute> routes;
}

/// The stops of [routes] within [radiusMeters] of the passenger, closest
/// first, at most [limit]. A stop shared by several routes (or both
/// directions) appears **once**, listing all of them. Stops without
/// coordinates are ignored. Computed on the phone from the catalogue already
/// loaded for the map (`routesWithPatterns`): no extra request.
List<NearbyStop> nearbyStops({
  required double latitude,
  required double longitude,
  required List<TransitRoute> routes,
  double radiusMeters = NearbyRoutesFilter.defaultRadiusMeters,
  int limit = 20,
}) {
  final byId =
      <String, ({PatternStop stop, double distance, List<StopRoute> routes})>{};
  for (final route in routes) {
    for (final pattern in route.patterns) {
      for (final stop in pattern.locatedStops) {
        final location = stop.location!;
        final distance = haversineMeters(
          latitude,
          longitude,
          location.latitude,
          location.longitude,
        );
        if (distance > radiusMeters) continue;
        // Same stop id = same physical stop; without one, same coordinates.
        final key = stop.stopId.isNotEmpty
            ? stop.stopId
            : '${location.latitude},${location.longitude}';
        final entry = byId.putIfAbsent(
          key,
          () => (stop: stop, distance: distance, routes: <StopRoute>[]),
        );
        final known = entry.routes.any(
          (r) => r.route.id == route.id && r.pattern.id == pattern.id,
        );
        if (!known) {
          entry.routes.add(StopRoute(route: route, pattern: pattern));
        }
      }
    }
  }

  final stops = [
    for (final MapEntry(:key, :value) in byId.entries)
      NearbyStop(
        stopId: key,
        name: value.stop.name,
        location: value.stop.location!,
        distanceMeters: value.distance,
        routes: value.routes
          ..sort((a, b) => a.route.code.compareTo(b.route.code)),
      ),
  ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return stops.length > limit ? stops.sublist(0, limit) : stops;
}
