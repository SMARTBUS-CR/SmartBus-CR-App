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

  /// `GET ops/driver/trips` — trips of the logged-in driver, earliest first,
  /// with their pattern and bus (`include=pattern,bus`, for the plate).
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
        'include': 'pattern,bus',
        'sort': 'scheduled_departure_at',
        'page[size]': '50',
      }),
    );
    final included = JsonApiIncluded(body['included']);
    return [
      for (final resource in _resources(body))
        DriverTrip.fromJsonApi(resource, included: included),
    ];
  }

  /// `POST ops/trips/{id}/start` — the trip becomes `in_progress`, so the GPS
  /// service starts accepting its locations. Starting a trip already in
  /// progress returns it again (idempotent).
  ///
  /// Errors: 409 the trip is not scheduled, 422 a business rule failed (bus or
  /// driver unavailable, departure suspended, another trip in progress), both
  /// with the backend message; 403 not the driver's trip; 404 not found.
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

  /// Results per page of [searchRoutes].
  static const searchPageSize = 20;

  /// Catalogue page size (the Dashboard maximum) and a safety cap of pages.
  static const _cataloguePageSize = 100;
  static const _maxCataloguePages = 50;

  Future<List<TransitRoute>>? _catalogue;

  /// Route search by **name, number or destination**, ignoring case and
  /// accents ("jose" finds "José", "pena" finds "Peña").
  ///
  /// The Dashboard filters (`filter[name]`, `filter[code]`) compare accents
  /// as they are (PostgreSQL `LIKE`) and there is no destination filter, so
  /// the public catalogue is downloaded once ([searchCatalogue]) and searched here.
  ///
  /// Order: exact number first, then routes whose number or name contains the
  /// text, then the ones that only match by destination; by number inside each
  /// group. [page] slices the results ([searchPageSize] per page).
  Future<RoutePage> searchRoutes(String query, {int page = 1}) async {
    final needle = foldForSearch(query.trim());
    final routes = await searchCatalogue();

    final ranked = <(int, TransitRoute)>[];
    for (final route in routes) {
      final code = foldForSearch(route.code);
      final int rank;
      if (code == needle) {
        rank = 0;
      } else if (code.contains(needle) ||
          foldForSearch(route.name).contains(needle)) {
        rank = 1;
      } else if (route.destinations.any(
        (destination) => foldForSearch(destination).contains(needle),
      )) {
        rank = 2;
      } else {
        continue;
      }
      ranked.add((rank, route));
    }
    ranked.sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      return byRank != 0 ? byRank : a.$2.code.compareTo(b.$2.code);
    });

    final start = (page - 1) * searchPageSize;
    final end = start + searchPageSize;
    return RoutePage(
      routes: [
        for (final (_, route) in ranked.skip(start).take(searchPageSize)) route,
      ],
      hasMore: ranked.length > end,
    );
  }

  /// `GET ops/routes?include=company,patterns` — every route of the public
  /// catalogue with its company and destinations, all pages. Downloaded once
  /// per service; a failure is not kept, so the next search tries again.
  Future<List<TransitRoute>> searchCatalogue() {
    final cached = _catalogue;
    if (cached != null) return cached;
    // Searches made while it downloads share the same request.
    final loading = _loadCatalogue();
    _catalogue = loading;
    loading.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_catalogue, loading)) _catalogue = null;
      },
    );
    return loading;
  }

  Future<List<TransitRoute>> _loadCatalogue() async {
    final routes = <TransitRoute>[];
    for (var page = 1; page <= _maxCataloguePages; page++) {
      final body = await _client.get(
        ApiConfig.opsRoutes({
          'include': 'company,patterns',
          'sort': 'code',
          'page[size]': '$_cataloguePageSize',
          'page[number]': '$page',
        }),
      );
      final included = JsonApiIncluded(body['included']);
      final patterns = _patternsById(body);
      routes.addAll([
        for (final resource in _resources(body))
          _withPatterns(resource, patterns, included: included),
      ]);
      if (!_hasNextPage(body)) break;
    }
    return routes;
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

    final patterns = _patternsById(body);
    return [
      for (final resource in _resources(body))
        _withPatterns(resource, patterns),
    ];
  }

  /// The `route-patterns` of the document's `included` array, by id.
  static Map<String, RoutePattern> _patternsById(Map<String, dynamic> body) => {
    for (final resource in _included(body, RoutePattern.jsonApiType))
      resource['id'].toString(): RoutePattern.fromJsonApi(resource),
  };

  /// [resource] with its own patterns: linked by `relationships.patterns.data`,
  /// or by the pattern's `route_id` when the route has no such relationship.
  static TransitRoute _withPatterns(
    Map<String, dynamic> resource,
    Map<String, RoutePattern> patterns, {
    JsonApiIncluded included = const JsonApiIncluded.empty(),
  }) {
    final routeId = resource['id'].toString();
    final linked = TransitRoute.linkedPatternIds(resource);
    final own = linked != null
        ? [for (final id in linked) ?patterns[id]]
        : (patterns.values.where((p) => p.routeId == routeId).toList()
            ..sort((a, b) => (a.code ?? '').compareTo(b.code ?? '')));
    return TransitRoute.fromJsonApi(
      resource,
      included: included,
      patterns: own,
    );
  }

  /// `GET ops/routes/{id}/patterns` — directions of a route with their stops.
  Future<List<RoutePattern>> routePatterns(String routeId) async {
    final body = await _client.get(ApiConfig.opsRoutePatterns(routeId));
    return _resources(body).map(RoutePattern.fromJsonApi).toList();
  }

  /// `GET ops/route-patterns/{id}` — one pattern with its line and stops
  /// (the driver's route when the trip has no planned snapshot).
  Future<RoutePattern> routePattern(String patternId) async =>
      RoutePattern.fromJsonApi(
        _resource(await _client.get(ApiConfig.opsRoutePattern(patternId))),
      );

  /// `GET ops/public/trips/{id}` — one trip without driver data (its
  /// `route_pattern_id`, status and bus), for the passenger's tracking map.
  Future<LiveBusTrip> publicTrip(String tripId) async =>
      LiveBusTrip.fromJsonApi(
        _resource(await _client.get(ApiConfig.opsPublicTrip(tripId))),
      );

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

  /// Laravel pagination: `meta.current_page` < `meta.last_page`, or a
  /// `links.next` URL.
  static bool _hasNextPage(Map<String, dynamic> body) {
    final meta = body['meta'];
    if (meta is Map) {
      final current = meta['current_page'];
      final last = meta['last_page'];
      if (current is num && last is num) return current < last;
    }
    final links = body['links'];
    return links is Map && links['next'] is String;
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
