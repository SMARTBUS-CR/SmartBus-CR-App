import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../trip_tracking/models/trip_tracking.dart';
import '../models/operations_models.dart';

/// Talks to the **Dashboard (operations) through the API Gateway** (`/ops/*`).
///
/// - Catalogue (routes, patterns, buses running): public, no token needed.
/// - Driver trips and start / complete: the token is attached by [ApiClient];
///   the Dashboard only lets the assigned driver act on a trip.
///
/// Errors arrive as `ApiException`, like every other service.
class OperationsService {
  OperationsService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  // --- Driver ------------------------------------------------------------------

  /// `GET ops/driver/trips` — trips of the logged-in driver, earliest first.
  /// Filter by [serviceDate] (local day) and/or [status].
  Future<List<DriverTrip>> driverTrips({
    DateTime? serviceDate,
    TripStatus? status,
  }) async {
    final date = serviceDate == null ? null : formatServiceDate(serviceDate);
    final body = await _client.get(
      ApiConfig.opsDriverTrips({
        'filter[service_date]': ?date,
        'filter[status]': ?_statusValue(status),
        'sort': 'scheduled_departure_at',
        'page[size]': '50',
      }),
    );
    return _resources(body).map(DriverTrip.fromJsonApi).toList();
  }

  /// `POST ops/trips/{id}/start` — the trip becomes `in_progress`, so the GPS
  /// service starts accepting its locations. 409 if it cannot be started.
  Future<DriverTrip> startTrip(String tripId) async => DriverTrip.fromJsonApi(
    _resource(await _client.post(ApiConfig.opsTripStart(tripId))),
  );

  /// `POST ops/trips/{id}/complete` — the trip becomes `completed`.
  Future<DriverTrip> completeTrip(String tripId) async =>
      DriverTrip.fromJsonApi(
        _resource(await _client.post(ApiConfig.opsTripComplete(tripId))),
      );

  // --- Passenger (public catalogue) -------------------------------------------

  /// `GET ops/routes` — active routes, sorted by code.
  Future<List<TransitRoute>> routes() async {
    final body = await _client.get(
      ApiConfig.opsRoutes({'sort': 'code', 'page[size]': '100'}),
    );
    return _resources(body).map(TransitRoute.fromJsonApi).toList();
  }

  /// `GET ops/routes?include=patterns` — active routes, each with its
  /// directions (line + ordered stops). **One request** for the whole map.
  ///
  /// The patterns arrive in the JSON:API `included` array. They are linked to
  /// their route by `relationships.patterns.data`, or by the pattern's
  /// `route_id` when the route has no such relationship.
  Future<List<TransitRoute>> routesWithPatterns() async {
    final body = await _client.get(
      ApiConfig.opsRoutes({
        'include': 'patterns',
        'sort': 'code',
        'page[size]': '100',
      }),
    );

    final patterns = <String, RoutePattern>{
      for (final resource in _included(body, RoutePattern.jsonApiType))
        resource['id'].toString(): RoutePattern.fromJsonApi(resource),
    };

    return [
      for (final resource in _resources(body))
        _withPatterns(resource, patterns),
    ];
  }

  static TransitRoute _withPatterns(
    Map<String, dynamic> resource,
    Map<String, RoutePattern> patterns,
  ) {
    final routeId = resource['id'].toString();
    final linked = TransitRoute.linkedPatternIds(resource);
    final own = linked != null
        ? [for (final id in linked) ?patterns[id]]
        : (patterns.values.where((p) => p.routeId == routeId).toList()
            ..sort((a, b) => (a.code ?? '').compareTo(b.code ?? '')));
    return TransitRoute.fromJsonApi(resource, patterns: own);
  }

  /// `GET ops/routes/{id}/patterns` — directions of a route with their stops.
  Future<List<RoutePattern>> routePatterns(String routeId) async {
    final body = await _client.get(ApiConfig.opsRoutePatterns(routeId));
    return _resources(body).map(RoutePattern.fromJsonApi).toList();
  }

  /// `GET ops/route-patterns/{id}/trips` — buses running now on a pattern.
  Future<List<LiveBusTrip>> ongoingTrips(String patternId) async {
    final body = await _client.get(
      ApiConfig.opsPatternTrips(patternId, {'page[size]': '50'}),
    );
    return _resources(body).map(LiveBusTrip.fromJsonApi).toList();
  }

  // --- helpers -------------------------------------------------------------------

  static String? _statusValue(TripStatus? status) => switch (status) {
    TripStatus.scheduled => 'scheduled',
    TripStatus.inProgress => 'in_progress',
    TripStatus.completed => 'completed',
    TripStatus.cancelled => 'cancelled',
    _ => null,
  };

  static Iterable<Map<String, dynamic>> _resources(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is! List) return const [];
    return data.whereType<Map>().map(Map<String, dynamic>.from);
  }

  /// Items of the JSON:API `included` array with the given [type].
  static Iterable<Map<String, dynamic>> _included(
    Map<String, dynamic> body,
    String type,
  ) {
    final included = body['included'];
    if (included is! List) return const [];
    return included
        .whereType<Map>()
        .where((item) => item['type'] == type && item['id'] != null)
        .map(Map<String, dynamic>.from);
  }

  static Map<String, dynamic> _resource(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is! Map) {
      throw const FormatException('operations: missing "data".');
    }
    return Map<String, dynamic>.from(data);
  }
}
