import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/operations/services/operations_service.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';

// JSON:API documents as the Dashboard returns them (through the Gateway), and
// an in-memory OperationsService for the screens.

const tripId = 'b0700000-0000-4000-8000-000000000002';
const patternId = 'a0600000-0000-4000-8000-000000000001';
const routeId = 'a0500000-0000-4000-8000-000000000001';

Map<String, dynamic> tripResource({
  String id = tripId,
  String status = 'scheduled',
  Object? snapshot = const {
    'route_code': 'PV-RF',
    'route_name': 'Puerto Viejo',
    'headsign': 'Puerto Viejo',
  },
}) => {
  'id': id,
  'type': 'trips',
  'attributes': {
    'route_pattern_id': patternId,
    'status': status,
    'service_date': '2026-11-11',
    'scheduled_departure_at': '2026-11-11T13:00:00.000000Z',
    'scheduled_arrival_at': '2026-11-11T14:00:00.000000Z',
    'actual_departure_at': null,
    'planned_route_snapshot': snapshot,
  },
};

Map<String, dynamic> routeResource() => {
  'id': routeId,
  'type': 'routes',
  'attributes': {'code': 'PV-RF', 'name': 'Puerto Viejo'},
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

DriverTrip driverTrip({String id = tripId, String status = 'scheduled'}) =>
    DriverTrip.fromJsonApi(tripResource(id: id, status: status));

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
}) => RoutePattern(
  id: id,
  name: 'Patrón $id',
  code: id,
  headsign: headsign,
  routeId: routeId,
  stops: stops,
  geometry: geometry,
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

  @override
  Future<DriverTrip> startTrip(String tripId) async {
    calls.add('start $tripId');
    if (startError != null) throw startError!;
    return driverTrip(status: 'in_progress');
  }

  @override
  Future<DriverTrip> completeTrip(String tripId) async {
    calls.add('complete $tripId');
    if (completeError != null) throw completeError!;
    return driverTrip(status: 'completed');
  }

  @override
  Future<List<TransitRoute>> routes() async {
    calls.add('routes');
    return routeList;
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

  @override
  Future<List<LiveBusTrip>> ongoingTrips(String patternId) async {
    calls.add('buses $patternId');
    return buses[patternId] ?? const [];
  }
}
