import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/location/location_service.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/bus_tracking_screen.dart';
import 'package:smartbus_drivers/features/passenger/map/passenger_map.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/gps_fix.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/gps_location_service.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/live_trip_tracker.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/trip_live_feed.dart';

import '../operations/operations_fixtures.dart';

const _tripId = '01a09332-3457-7315-885e-4ebb218f7262';

class _FakeMap implements PassengerMapHandle {
  final List<BusMarker?> buses = [];
  final List<({double lat, double lng})> moves = [];
  final List<DeviceLocation> users = [];
  final List<List<GeoPoint>> fits = [];
  RoutePattern? route;

  @override
  Future<void> moveTo(
    double latitude,
    double longitude, {
    double? zoom,
  }) async => moves.add((lat: latitude, lng: longitude));

  @override
  Future<void> showUserLocation(DeviceLocation location) async =>
      users.add(location);

  @override
  Future<void> showBus(BusMarker? bus) async => buses.add(bus);

  @override
  Future<void> showBuses(List<BusMarker> buses) async {}

  @override
  Future<void> showRoute(RoutePattern pattern) async => route = pattern;

  @override
  Future<void> clearRoute() async => route = null;

  PatternStop? highlighted;

  @override
  Future<void> highlightStop(PatternStop? stop) async => highlighted = stop;

  @override
  Future<void> fitBounds(
    List<GeoPoint> points, {
    EdgeInsets padding = EdgeInsets.zero,
  }) async => fits.add(points);

  PassengerMapBuilder get builder =>
      (context, options) =>
          _FakeMapWidget(onReady: () => options.onReady(this));
}

class _FakeMapWidget extends StatefulWidget {
  const _FakeMapWidget({required this.onReady});

  final VoidCallback onReady;

  @override
  State<_FakeMapWidget> createState() => _FakeMapWidgetState();
}

class _FakeMapWidgetState extends State<_FakeMapWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady());
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.grey);
}

class _FakeGps implements GpsLocationService {
  _FakeGps(this.next);

  TripTracking next;
  ApiException? error;

  @override
  Future<TripTracking> latestForTrip(String tripId) async {
    if (error != null) throw error!;
    return next;
  }

  @override
  Future<String?> send(GpsFix fix) => throw UnimplementedError();

  @override
  Future<String> authorizeChannel({
    required String socketId,
    required String channelName,
  }) => throw UnimplementedError();
}

class _FakeFeed implements TripLiveFeed {
  final StreamController<BusLocationUpdate> _locations =
      StreamController.broadcast(sync: true);
  final ValueNotifier<bool> _connected = ValueNotifier(true);

  @override
  Stream<BusLocationUpdate> get locations => _locations.stream;

  @override
  ValueListenable<bool> get connected => _connected;

  @override
  Stream<Object> get rejections => const Stream.empty();

  @override
  void follow(String tripId) {}

  @override
  Future<void> dispose() async {}

  void push(BusPosition position) => _locations.add(
    BusLocationUpdate(tripId: _tripId, busId: 'bus', position: position),
  );
}

class _FakeLocation extends LocationService {
  _FakeLocation({this.access = LocationAccess.granted, this.location});

  final LocationAccess access;
  final DeviceLocation? location;
  final StreamController<DeviceLocation> updates = StreamController();
  final List<bool> accessChecks = [];

  @override
  Future<LocationAccess> checkAccess({bool request = true}) async {
    accessChecks.add(request);
    return access;
  }

  @override
  Future<DeviceLocation?> currentLocation() async => location;

  @override
  Stream<DeviceLocation> watch() => updates.stream;
}

const _passenger = DeviceLocation(
  latitude: 9.93,
  longitude: -84.08,
  accuracyMeters: 10,
);

BusPosition _position({double lat = 9.93, int second = 0}) => BusPosition(
  latitude: lat,
  longitude: -84.08,
  speedKmh: 38.4,
  recordedAt: DateTime.utc(2026, 11, 9, 15, 0, second),
);

TripTracking _tracking(TripStatus status, {BusPosition? position}) =>
    TripTracking(
      tripId: _tripId,
      status: status,
      freshness: TrackingFreshness.live,
      position: position,
      ageSeconds: position == null ? null : 0,
    );

void main() {
  late _FakeMap map;
  late _FakeFeed feed;
  late DateTime now;

  setUp(() {
    map = _FakeMap();
    feed = _FakeFeed();
    now = DateTime.utc(2026, 11, 9, 15);
  });

  Future<void> pump(
    WidgetTester tester,
    _FakeGps gps, {
    _FakeLocation? location,
    FakeOperations? operations,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BusTrackingScreen(
          tripId: _tripId,
          operations: operations ?? FakeOperations(),
          mapBuilder: map.builder,
          locationService: location ?? _FakeLocation(),
          clock: () => now,
          trackerFactory: (tripId) => LiveTripTracker(
            tripId: tripId,
            service: gps,
            feed: feed,
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pump(); // GET
    await tester.pump(); // map ready
  }

  /// Moves both the fake time and this test's clock.
  Future<void> wait(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  testWidgets('trip in progress: the bus is on the map, live, centered', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
    );

    expect(find.text('En vivo'), findsOneWidget);
    expect(find.textContaining('38 km/h'), findsOneWidget);
    expect(
      map.buses.last,
      const BusMarker(latitude: 9.93, longitude: -84.08, live: true),
    );
    expect(map.moves.single, (lat: 9.93, lng: -84.08));
    expect(find.byKey(const Key('center-bus-button')), findsOneWidget);
  });

  testWidgets('shows the passenger too, even at the same spot as the bus', (
    tester,
  ) async {
    final location = _FakeLocation(location: _passenger);
    await pump(
      tester,
      _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
      location: location,
    );

    // Same coordinates: both are drawn (the bus pin points at the dot).
    expect(map.users.last, same(_passenger));
    expect(map.buses.last, isNotNull);
    expect(location.accessChecks, [false]); // never asks for permission here

    const moved = DeviceLocation(latitude: 9.94, longitude: -84.07);
    location.updates.add(moved);
    await tester.pump();
    expect(map.users.last, same(moved));
  });

  testWidgets('without location permission: only the bus is drawn', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
      location: _FakeLocation(
        access: LocationAccess.denied,
        location: _passenger,
      ),
    );

    expect(map.users, isEmpty);
    expect(map.buses.last, isNotNull);
    expect(find.text('En vivo'), findsOneWidget);
  });

  testWidgets('a BusLocationUpdated moves the marker without reloading', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
    );

    feed.push(_position(lat: 9.95, second: 5));
    await tester.pump();

    expect(map.buses.last!.latitude, 9.95);
    // Without a route the camera follows the bus.
    expect(map.moves.last, (lat: 9.95, lng: -84.08));
    final moves = map.moves.length;

    // The once-a-second redraw does not move the camera again.
    await wait(tester, const Duration(seconds: 2));
    expect(map.moves, hasLength(moves));
  });

  group('route of the trip', () {
    FakeOperations withRoute() => FakeOperations()
      ..publicTripResult = LiveBusTrip.fromJsonApi(liveTripResource())
      ..patternById = pattern(
        patternId,
        stops: [
          stopAt('Terminal', 9.92, -84.08, seq: 1),
          stopAt('Centro', 9.94, -84.08, seq: 2),
        ],
      );

    testWidgets('draws the route of the trip with the bus inside it', (
      tester,
    ) async {
      final operations = withRoute();
      await pump(
        tester,
        _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
        operations: operations,
      );
      await tester.pump();

      expect(operations.calls, ['publicTrip $_tripId', 'pattern $patternId']);
      expect(map.route?.stops.map((s) => s.name), ['Terminal', 'Centro']);
      // First view: the whole route plus the bus.
      expect(map.fits.last, hasLength(3));
      expect(map.fits.last.last.latitude, 9.93);
      expect(find.byKey(const Key('show-route-button')), findsOneWidget);

      // The bus moves inside the route view (no camera jump).
      final moves = map.moves.length;
      feed.push(_position(lat: 9.935, second: 5));
      await tester.pump();
      expect(map.buses.last!.latitude, 9.935);
      expect(map.moves, hasLength(moves));
    });

    testWidgets('"Ver el bus" follows it; "Ver ruta" shows the whole route', (
      tester,
    ) async {
      await pump(
        tester,
        _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
        operations: withRoute(),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('center-bus-button')));
      await tester.pump();
      feed.push(_position(lat: 9.936, second: 5));
      await tester.pump();
      expect(map.moves.last, (lat: 9.936, lng: -84.08));

      final fits = map.fits.length;
      await tester.tap(find.byKey(const Key('show-route-button')));
      await tester.pump();
      expect(map.fits, hasLength(fits + 1));
      final moves = map.moves.length;
      feed.push(_position(lat: 9.937, second: 10));
      await tester.pump();
      expect(map.moves, hasLength(moves)); // not following any more
    });

    testWidgets('my position: the stop to walk to, highlighted on the map', (
      tester,
    ) async {
      await pump(
        tester,
        _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
        operations: withRoute(),
        location: _FakeLocation(
          location: const DeviceLocation(latitude: 9.95, longitude: -84.08),
        ),
      );
      await tester.pump();

      // The bus (9.93) already left the terminal (9.92): "Centro" (9.94).
      expect(find.text('Tu parada: Centro'), findsOneWidget);
      expect(find.text('A 1,1 km · ~14 min caminando'), findsOneWidget);
      expect(find.text('Es la próxima parada del bus.'), findsOneWidget);
      expect(map.highlighted?.name, 'Centro');
      expect(map.users.last.latitude, 9.95);

      // "Cómo llegar": me, my stop and the bus in one view.
      await tester.tap(find.byKey(const Key('boarding-action')));
      await tester.pump();
      expect(map.fits.last.map((p) => p.latitude), [9.95, 9.94, 9.93]);
    });

    testWidgets('without location: offers to turn it on (asked on tap only)', (
      tester,
    ) async {
      final location = _FakeLocation(access: LocationAccess.denied);
      await pump(
        tester,
        _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
        operations: withRoute(),
        location: location,
      );
      await tester.pump();

      expect(find.text('¿Dónde tomo el bus?'), findsOneWidget);
      expect(location.accessChecks, [false]); // not asked on opening

      await tester.tap(find.byKey(const Key('boarding-action')));
      await tester.pump();
      expect(location.accessChecks, [false, true]); // asked on "Activar"
    });

    testWidgets('no line from the Dashboard: "Ruta aproximada"', (
      tester,
    ) async {
      await pump(
        tester,
        _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
        operations: withRoute(),
      );
      await tester.pump();

      expect(map.route?.hasGeometry, isFalse);
      expect(find.byKey(const Key('approximate-route-note')), findsOneWidget);
    });

    testWidgets('with the Dashboard line: drawn as it comes, no note', (
      tester,
    ) async {
      const line = [
        GeoPoint(9.92, -84.08),
        GeoPoint(9.925, -84.085),
        GeoPoint(9.94, -84.08),
      ];
      final operations = withRoute()
        ..patternById = pattern(
          patternId,
          stops: [
            stopAt('Terminal', 9.92, -84.08, seq: 1),
            stopAt('Centro', 9.94, -84.08, seq: 2),
          ],
          geometry: line,
        );
      await pump(
        tester,
        _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
        operations: operations,
      );
      await tester.pump();

      expect(map.route?.path, line);
      expect(find.byKey(const Key('approximate-route-note')), findsNothing);
    });

    testWidgets('no route available: bus only, no "Ver ruta"', (tester) async {
      await pump(
        tester,
        _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
      );
      await tester.pump();

      expect(map.route, isNull);
      expect(find.byKey(const Key('show-route-button')), findsNothing);
      expect(map.buses.last, isNotNull);
    });
  });

  testWidgets('no new positions: weak signal, then no signal (gray bus)', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
    );

    await wait(tester, const Duration(seconds: 40));
    expect(find.text('Señal débil'), findsOneWidget);
    expect(map.buses.last!.live, isFalse);

    await wait(tester, const Duration(minutes: 5));
    expect(find.text('Sin señal del bus'), findsOneWidget);
  });

  testWidgets('scheduled trip: "aún no inicia", no bus', (tester) async {
    await pump(tester, _FakeGps(_tracking(TripStatus.scheduled)));

    expect(find.text('El viaje aún no inicia'), findsOneWidget);
    expect(map.buses.whereType<BusMarker>(), isEmpty);
  });

  testWidgets('completed trip: "Viaje finalizado", no bus', (tester) async {
    await pump(
      tester,
      _FakeGps(_tracking(TripStatus.completed, position: _position())),
    );

    expect(find.text('Viaje finalizado'), findsOneWidget);
    expect(map.buses.whereType<BusMarker>(), isEmpty);
    expect(find.byKey(const Key('center-bus-button')), findsNothing);
  });

  testWidgets('cancelled trip: "Viaje cancelado"', (tester) async {
    await pump(tester, _FakeGps(_tracking(TripStatus.cancelled)));

    expect(find.text('Viaje cancelado'), findsOneWidget);
  });

  testWidgets('trip not found', (tester) async {
    final gps = _FakeGps(_tracking(TripStatus.inProgress))
      ..error = ApiException.fromStatus(404);
    await pump(tester, gps);

    expect(find.text('No encontramos este viaje'), findsOneWidget);
  });

  testWidgets('no connection: message and "Reintentar"', (tester) async {
    final gps = _FakeGps(
      _tracking(TripStatus.inProgress, position: _position()),
    )..error = ApiException.noConnection;
    await pump(tester, gps);

    expect(find.text('No se pudo cargar el viaje'), findsOneWidget);
    expect(find.text('Sin conexión a Internet.'), findsOneWidget);

    gps.error = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();

    expect(find.text('En vivo'), findsOneWidget);
  });

  testWidgets('real time down: shows that it is reconnecting', (tester) async {
    feed._connected.value = false;
    await pump(
      tester,
      _FakeGps(_tracking(TripStatus.inProgress, position: _position())),
    );

    expect(find.byKey(const Key('reconnecting-hint')), findsOneWidget);
  });
}
