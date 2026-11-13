import 'dart:async';

import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/operations/services/operations_service.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';

// JSON:API documents as the Dashboard returns them (through the Gateway), and
// an in-memory OperationsService for the screens.

const tripId = 'b0700000-0000-4000-8000-000000000002';
const patternId = 'a0600000-0000-4000-8000-000000000001';
const routeId = 'a0500000-0000-4000-8000-000000000001';

const busId = 'b0300000-0000-4000-8000-000000000001';

Map<String, dynamic> tripResource({
  String id = tripId,
  String status = 'scheduled',
  Object? snapshot = const {
    'route_code': 'PV-RF',
    'route_name': 'Puerto Viejo',
    'headsign': 'Puerto Viejo',
  },
  String? actualDepartureAt,
  String? actualArrivalAt,
  bool withRelationships = false,
}) => {
  'id': id,
  'type': 'trips',
  'attributes': {
    'route_pattern_id': patternId,
    'status': status,
    'service_date': '2026-11-11',
    'scheduled_departure_at': '2026-11-11T13:00:00.000000Z',
    'scheduled_arrival_at': '2026-11-11T14:00:00.000000Z',
    'actual_departure_at': actualDepartureAt,
    'actual_arrival_at': actualArrivalAt,
    'planned_route_snapshot': snapshot,
  },
  if (withRelationships)
    'relationships': {
      'bus': {
        'data': {'type': 'buses', 'id': busId},
      },
      'pattern': {
        'data': {'type': 'route-patterns', 'id': patternId},
      },
    },
};

/// `included` of `GET ops/driver/trips?include=pattern,bus`.
List<Map<String, dynamic>> driverTripsIncluded() => [
  {
    'id': busId,
    'type': 'buses',
    'attributes': {'plate_number': 'SJB-1234', 'unit_number': '07'},
  },
  {
    'id': patternId,
    'type': 'route-patterns',
    'attributes': {'code': 'PV-RF-1', 'headsign': 'Terminal Puerto Viejo'},
  },
];

Map<String, dynamic> routeResource() => {
  'id': routeId,
  'type': 'routes',
  'attributes': {'code': 'PV-RF', 'name': 'Puerto Viejo'},
};

const companyId = 'c0100000-0000-4000-8000-000000000001';

/// A route of a `GET ops/routes?include=company,patterns` document.
Map<String, dynamic> searchRouteResource({
  required String id,
  required String code,
  required String name,
  List<String> patternIds = const [],
}) => {
  'id': id,
  'type': 'routes',
  'attributes': {'code': code, 'name': name, 'company_id': companyId},
  'relationships': {
    'company': {
      'data': {'type': 'companies', 'id': companyId},
    },
    'patterns': {
      'data': [
        for (final patternId in patternIds)
          {'type': 'route-patterns', 'id': patternId},
      ],
    },
  },
};

/// `included` of a route search: the company and two directions.
List<Map<String, dynamic>> searchIncluded() => [
  {
    'id': companyId,
    'type': 'companies',
    'attributes': {
      'legal_name': 'Transportes Heredianos S.A.',
      'trade_name': 'TUASA',
    },
  },
  {
    'id': 'p-1',
    'type': 'route-patterns',
    'attributes': {'code': '400-1', 'headsign': 'Heredia'},
  },
  {
    'id': 'p-2',
    'type': 'route-patterns',
    'attributes': {'code': '400-2', 'headsign': 'San José'},
  },
];

/// A page of `GET ops/routes` (Laravel pagination meta).
Map<String, dynamic> searchDocument(
  List<Map<String, dynamic>> routes, {
  int currentPage = 1,
  int lastPage = 1,
}) => {
  'data': routes,
  'included': searchIncluded(),
  'meta': {'current_page': currentPage, 'last_page': lastPage},
};

Map<String, dynamic> patternResource({
  Object? geometry = const {
    'type': 'LineString',
    'coordinates': [
      [-83.99, 10.46],
      [-83.98, 10.47],
    ],
  },
}) => {
  'id': patternId,
  'type': 'route-patterns',
  'attributes': {
    'code': 'PV-RF-1',
    'name': 'Sarapiquí – Puerto Viejo',
    'headsign': 'Puerto Viejo',
    'route_id': routeId,
    'route_geometry': geometry,
    'driving_duration_seconds': 1500.0,
    // Out of order on purpose: the app sorts by stop_sequence.
    'stops': [
      {
        'stop_id': 's2',
        'stop_name': 'Centro',
        'stop_sequence': 2,
        'minutes_from_start': 12,
        'latitude': 10.47,
        'longitude': -83.98,
      },
      {
        'stop_id': 's1',
        'stop_name': 'Terminal',
        'stop_sequence': 1,
        'minutes_from_start': 0,
        'latitude': 10.46,
        'longitude': -83.99,
      },
    ],
  },
};

Map<String, dynamic> liveTripResource({String id = tripId}) => {
  'id': id,
  'type': 'trips',
  'attributes': {
    'route_pattern_id': patternId,
    'status': 'in_progress',
    'scheduled_departure_at': '2026-11-11T13:00:00.000000Z',
    'actual_departure_at': '2026-11-11T13:05:00.000000Z',
    'headsign': 'Puerto Viejo',
    'bus': {'id': 'bus-1', 'plate_number': 'ABC-123', 'unit_number': '12'},
  },
};

DriverTrip driverTrip({
  String id = tripId,
  String status = 'scheduled',
  String? actualDepartureAt,
  String? actualArrivalAt,
  Object? snapshot = const {
    'route_code': 'PV-RF',
    'route_name': 'Puerto Viejo',
    'headsign': 'Puerto Viejo',
  },
}) => DriverTrip.fromJsonApi(
  tripResource(
    id: id,
    status: status,
    actualDepartureAt: actualDepartureAt,
    actualArrivalAt: actualArrivalAt,
    snapshot: snapshot,
  ),
);

/// `actual_arrival_at` that [FakeOperations.completeTrip] answers (UTC).
const completedArrivalAt = '2026-11-11T14:07:00.000000Z';

/// `planned_route_snapshot` as the Dashboard stores it: the line and three
/// stops (`lat` / `lng` as strings), out of order on purpose.
const Map<String, dynamic> plannedSnapshot = {
  'schema_version': 1,
  'pattern_id': patternId,
  'pattern_code': 'PV-RF-1',
  'pattern_name': 'Sarapiquí – Puerto Viejo',
  'headsign': 'Puerto Viejo',
  'route_id': routeId,
  'route_code': 'PV-RF',
  'route_name': 'Puerto Viejo',
  'route_geometry': {
    'type': 'LineString',
    'coordinates': [
      [-84.000, 10.460],
      [-84.000, 10.470],
      [-84.000, 10.480],
    ],
  },
  'distance_meters': '2200',
  'occurrences': [
    {
      'stop_id': 's2',
      'name': 'Centro',
      'stop_sequence': 2,
      'lat': '10.470',
      'lng': '-84.000',
      'minutes_from_start': 10,
    },
    {
      'stop_id': 's1',
      'name': 'Terminal',
      'stop_sequence': 1,
      'lat': '10.460',
      'lng': '-84.000',
      'minutes_from_start': 0,
    },
    {
      'stop_id': 's3',
      'name': 'Muelle',
      'stop_sequence': 3,
      'lat': '10.480',
      'lng': '-84.000',
      'minutes_from_start': 20,
    },
  ],
};

/// A stop at [lat], [lng] (order = [seq]).
PatternStop stopAt(
  String name,
  double lat,
  double lng, {
  required int seq,
  int? minutes,
}) => PatternStop(
  stopId: 'stop-$name',
  name: name,
  sequence: seq,
  minutesFromStart: minutes,
  latitude: lat,
  longitude: lng,
);

/// A pattern with [stops]; [geometry] empty = no `route_geometry`.
RoutePattern pattern(
  String id, {
  String? headsign,
  List<PatternStop> stops = const [],
  List<GeoPoint> geometry = const [],
  String? routeId,
  double? drivingSeconds,
}) => RoutePattern(
  id: id,
  name: 'Patrón $id',
  code: id,
  headsign: headsign,
  routeId: routeId,
  stops: stops,
  geometry: geometry,
  drivingDurationSeconds: drivingSeconds,
);

TransitRoute route(
  String id, {
  required String code,
  required String name,
  List<RoutePattern> patterns = const [],
}) => TransitRoute(id: id, code: code, name: name, patterns: patterns);

/// OperationsService with canned answers; records what the screens call.
class FakeOperations extends OperationsService {
  FakeOperations({
    this.trips = const [],
    this.otherDayTrips = const [],
    this.routeList = const [],
    this.patterns = const [],
    this.buses = const {},
    this.catalogue = const [],
    this.catalogueError,
    this.startError,
    this.completeError,
  });

  /// Today's trips (`serviceDate` filter).
  List<DriverTrip> trips;

  /// Trips of other days: only returned when filtering by status.
  List<DriverTrip> otherDayTrips;
  List<TransitRoute> routeList;
  List<RoutePattern> patterns;
  Map<String, List<LiveBusTrip>> buses;

  /// Routes with their patterns (`routesWithPatterns`, the home map).
  List<TransitRoute> catalogue;

  /// Thrown by `routesWithPatterns` while not null.
  Exception? catalogueError;
  Exception? startError;
  Exception? completeError;

  final List<String> calls = [];
  TripStatus? lastStatusFilter;

  @override
  Future<List<DriverTrip>> driverTrips({
    DateTime? serviceDate,
    TripStatus? status,
  }) async {
    calls.add('driverTrips');
    if (status == null) return trips;
    lastStatusFilter = status;
    return [
      ...trips,
      ...otherDayTrips,
    ].where((trip) => trip.status == status).toList();
  }

  /// Pages of [driverTripHistory] (1-based) for every status; filtered by
  /// status here. [historyError] fails the next calls.
  List<List<DriverTrip>> historyPages = const [];
  Exception? historyError;

  /// While not null, [driverTripHistory] waits for it.
  Completer<void>? historyGate;

  @override
  Future<DriverTripPage> driverTripHistory({
    int page = 1,
    TripStatus? status,
  }) async {
    calls.add('history $page${status == null ? '' : ' ${status.name}'}');
    await historyGate?.future;
    if (historyError != null) throw historyError!;
    if (status != null) {
      // Filtered: everything that matches, in one page.
      return DriverTripPage(
        trips: [
          for (final trips in historyPages)
            ...trips.where((t) => t.status == status),
        ],
        hasMore: false,
      );
    }
    return DriverTripPage(
      trips: page <= historyPages.length ? historyPages[page - 1] : const [],
      hasMore: page < historyPages.length,
    );
  }

  /// While not null, [startTrip] waits for it (to see the spinner).
  Completer<void>? startGate;

  @override
  Future<DriverTrip> startTrip(String tripId) async {
    calls.add('start $tripId');
    await startGate?.future;
    if (startError != null) throw startError!;
    return driverTrip(
      id: tripId,
      status: 'in_progress',
      actualDepartureAt: '2026-11-11T13:05:00.000000Z',
    );
  }

  /// While not null, [completeTrip] waits for it (to see the spinner).
  Completer<void>? completeGate;

  @override
  Future<DriverTrip> completeTrip(String tripId) async {
    calls.add('complete $tripId');
    await completeGate?.future;
    if (completeError != null) throw completeError!;
    return driverTrip(
      status: 'completed',
      actualDepartureAt: '2026-11-11T13:05:00.000000Z',
      actualArrivalAt: completedArrivalAt,
    );
  }

  /// Status that [trip] answers (`GET ops/trips/{id}`). While `null` it
  /// answers [knownTrip] (or the trip of [trips] with that id) unchanged, so
  /// opening a screen does not change the trip it shows.
  String? tripStatus;

  /// The trip the screen was opened with (set by the test helpers).
  DriverTrip? knownTrip;
  Exception? tripError;

  /// While not null, [trip] waits for it (to see the refresh indicator).
  Completer<void>? tripGate;

  @override
  Future<DriverTrip> trip(String tripId) async {
    calls.add('trip $tripId');
    await tripGate?.future;
    if (tripError != null) throw tripError!;
    final status = tripStatus;
    if (status != null) {
      return driverTrip(
        id: tripId,
        status: status,
        actualArrivalAt: status == 'completed' ? completedArrivalAt : null,
      );
    }
    final known = [
      ?knownTrip,
      ...trips,
      ...otherDayTrips,
    ].where((t) => t.id == tripId).firstOrNull;
    return known ?? driverTrip(id: tripId, status: 'in_progress');
  }

  @override
  Future<List<TransitRoute>> routes() async {
    calls.add('routes');
    return routeList;
  }

  /// Answers of [searchRoutes]; by default no route matches.
  Future<RoutePage> Function(String query, int page)? onSearch;

  @override
  Future<RoutePage> searchRoutes(String query, {int page = 1}) {
    calls.add('search $query $page');
    final handler = onSearch;
    if (handler == null) {
      return Future.value(const RoutePage(routes: [], hasMore: false));
    }
    return handler(query, page);
  }

  @override
  Future<List<TransitRoute>> routesWithPatterns() async {
    calls.add('routesWithPatterns');
    if (catalogueError != null) throw catalogueError!;
    return catalogue;
  }

  @override
  Future<List<RoutePattern>> routePatterns(String routeId) async {
    calls.add('patterns $routeId');
    return patterns;
  }

  /// Answer of [routePattern] (`GET ops/route-patterns/{id}`); `null` = 404.
  RoutePattern? patternById;

  @override
  Future<RoutePattern> routePattern(String patternId) async {
    calls.add('pattern $patternId');
    final pattern = patternById;
    if (pattern == null) {
      throw const ApiException(ApiErrorType.notFound, 'No encontrado');
    }
    return pattern;
  }

  /// Answer of [publicTrip]; `null` = 404.
  LiveBusTrip? publicTripResult;

  @override
  Future<LiveBusTrip> publicTrip(String tripId) async {
    calls.add('publicTrip $tripId');
    final trip = publicTripResult;
    if (trip == null) {
      throw const ApiException(ApiErrorType.notFound, 'No encontrado');
    }
    return trip;
  }

  @override
  Future<List<LiveBusTrip>> ongoingTrips(String patternId) async {
    calls.add('buses $patternId');
    return buses[patternId] ?? const [];
  }

  /// Fares by route id, and weekly departures by pattern id. Their requests
  /// go to [timetableCalls] (not [calls], whose order other tests check).
  Map<String, List<RouteFare>> fares = const {};
  Map<String, List<RouteSchedule>> schedules = const {};
  final List<String> timetableCalls = [];

  /// "Próximas salidas" and "¿Cómo llego?".
  final FakePlanning planning = FakePlanning();

  /// When set, [routeFares] and [patternSchedules] fail with it.
  ApiException? timetableError;

  @override
  Future<List<RouteFare>> routeFares(String routeId) async {
    timetableCalls.add('fares $routeId');
    if (timetableError != null) throw timetableError!;
    return fares[routeId] ?? const [];
  }

  @override
  Future<List<StopDeparture>> stopDepartures(
    String stopId, {
    DateTime? from,
    Duration window = const Duration(hours: 2),
  }) async {
    planning.calls.add('departures $stopId');
    if (planning.error != null) throw planning.error!;
    return planning.departures[stopId] ?? const [];
  }

  @override
  Future<List<Journey>> journeys({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    int walkingRadiusMeters = 800,
    DateTime? departureAt,
  }) async {
    planning.calls.add('journeys $destinationLatitude,$destinationLongitude');
    await planning.journeysGate?.future;
    if (planning.error != null) throw planning.error!;
    return planning.journeys;
  }

  @override
  Future<List<RouteSchedule>> patternSchedules(String patternId) async {
    timetableCalls.add('schedules $patternId');
    if (timetableError != null) throw timetableError!;
    return schedules[patternId] ?? const [];
  }
}

/// Answers of "Próximas salidas" / "¿Cómo llego?" for [FakeOperations].
class FakePlanning {
  /// Departures by stop id.
  Map<String, List<StopDeparture>> departures = {};

  /// Answer of `journeys`.
  List<Journey> journeys = const [];

  /// When set, both fail with it.
  ApiException? error;

  /// While not null, `journeys` waits for it.
  Completer<void>? journeysGate;

  /// Requests, in order: `departures STOP`, `journeys LAT,LNG`.
  final List<String> calls = [];
}

/// A fare of ₡[amount] with no validity limits.
RouteFare fare(double amount) => RouteFare(amount: amount, currency: 'CRC');

/// A departure every [dayOfWeek] (0 = Sunday) at [hour]:[minute].
RouteSchedule departure(int dayOfWeek, int hour, [int minute = 0]) =>
    RouteSchedule(dayOfWeek: dayOfWeek, hour: hour, minute: minute);
