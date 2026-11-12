import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/location/location_service.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/driver/trip_screen.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/map/passenger_map.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/trip_location_sender.dart';

import '../operations/operations_fixtures.dart';

/// Sender without the device GPS: only records start / stop.
class _FakeSender extends TripLocationSender {
  final List<String> started = [];
  int stops = 0;

  @override
  Future<void> start({required String tripId}) async {
    started.add(tripId);
    snapshot.value = TripTrackingSnapshot(
      state: TripTrackingState.tracking,
      tripId: tripId,
    );
  }

  @override
  void stop() {
    stops++;
    snapshot.value = snapshot.value.copyWith(state: TripTrackingState.stopped);
  }

  /// The GPS service answered 401 (what the real sender reports).
  void rejectSession() {
    snapshot.value = snapshot.value.copyWith(
      state: TripTrackingState.rejected,
      lastError: 'Tu sesión expiró. Inicia sesión nuevamente.',
      sessionExpired: true,
    );
  }

  /// A new GPS reading of the bus.
  void moveTo(double latitude, double longitude) {
    snapshot.value = snapshot.value.copyWith(
      latitude: latitude,
      longitude: longitude,
      sentCount: snapshot.value.sentCount + 1,
      lastSentAt: DateTime.now(),
    );
  }
}

/// Map without MapLibre: records what the screen draws.
class _FakeMap implements PassengerMapHandle {
  RoutePattern? route;
  final List<BusMarker?> buses = [];
  final List<List<GeoPoint>> fits = [];
  final List<({double lat, double lng})> moves = [];
  PatternStop? highlighted;

  @override
  Future<void> moveTo(
    double latitude,
    double longitude, {
    double? zoom,
  }) async => moves.add((lat: latitude, lng: longitude));

  @override
  Future<void> showUserLocation(DeviceLocation location) async {}

  @override
  Future<void> showBus(BusMarker? bus) async => buses.add(bus);

  @override
  Future<void> showBuses(List<BusMarker> buses) async {}

  @override
  Future<void> showRoute(RoutePattern pattern) async => route = pattern;

  @override
  Future<void> clearRoute() async => route = null;

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

Future<_FakeMap> _pumpTrip(
  WidgetTester tester, {
  required FakeOperations operations,
  required _FakeSender sender,
  String? status,
  DriverTrip? trip,
  bool autoStart = false,
}) async {
  final map = _FakeMap();
  await tester.pumpWidget(
    MaterialApp(
      home: TripScreen(
        trip: trip ?? (status == null ? null : driverTrip(status: status)),
        autoStart: autoStart,
        operations: operations,
        sender: sender,
        sessionStore: SecureSessionStore(),
        mapBuilder: map.builder,
      ),
      routes: {
        '/driver/home': (_) => const Scaffold(body: Text('home')),
        '/driver/routes': (_) => const Scaffold(body: Text('routes')),
        '/login': (_) => const Scaffold(body: Text('login')),
      },
    ),
  );
  await tester.pump();
  await tester.pump();
  return map;
}

/// The "Enviando ubicación · hace …" status line (rich text).
final _sending = find.textContaining('Enviando ubicación', findRichText: true);

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({'sb_access_token': 'tok'}),
  );

  group('GPS across tabs (the sender outlives the screen)', () {
    testWidgets('leaving "Recorrido" does not stop the GPS', (tester) async {
      final operations = FakeOperations(
        trips: [driverTrip(status: 'in_progress')],
      );
      final sender = _FakeSender();
      await _pumpTrip(
        tester,
        operations: operations,
        sender: sender,
        status: 'in_progress',
        autoStart: true,
      );
      expect(sender.started, [tripId]);

      // The driver opens another tab: the trip screen is replaced.
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushReplacementNamed('/driver/routes');
      await tester.pumpAndSettle();
      expect(find.text('routes'), findsOneWidget);

      expect(sender.stops, 0);
      expect(sender.snapshot.value.isTracking, isTrue);

      // Back on "Recorrido" (from the tab, no trip): still sending, not
      // started a second time.
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => TripScreen(
                operations: operations,
                sender: sender,
                sessionStore: SecureSessionStore(),
                mapBuilder: _FakeMap().builder,
              ),
            ),
          );
      await tester.pumpAndSettle();
      expect(_sending, findsOneWidget);
      expect(sender.started, [tripId]);
    });

    testWidgets('"Continuar" on the same trip does not restart it', (
      tester,
    ) async {
      final sender = _FakeSender();
      await sender.start(tripId: tripId);
      await _pumpTrip(
        tester,
        operations: FakeOperations(),
        sender: sender,
        status: 'in_progress',
        autoStart: true,
      );

      expect(sender.started, [tripId]);
      expect(sender.stops, 0);
    });
  });

  group('map with the route to follow', () {
    DriverTrip plannedTrip() => driverTrip(
      status: 'in_progress',
      actualDepartureAt: '2026-11-11T13:00:00.000000Z',
      snapshot: plannedSnapshot,
    );

    testWidgets('draws the planned route of the trip (no extra request)', (
      tester,
    ) async {
      final operations = FakeOperations();
      final map = await _pumpTrip(
        tester,
        operations: operations,
        sender: _FakeSender(),
        trip: plannedTrip(),
        autoStart: true,
      );

      expect(map.route?.id, patternId);
      expect(map.route?.stops.map((s) => s.name), [
        'Terminal',
        'Centro',
        'Muelle',
      ]);
      expect(map.route?.hasGeometry, isTrue);
      expect(map.fits, isNotEmpty); // whole route until the first position
      expect(operations.calls.where((c) => c.startsWith('pattern')), isEmpty);
      expect(find.byKey(const Key('no-route-note')), findsNothing);
      expect(find.text('3 paradas en este recorrido'), findsOneWidget);
    });

    testWidgets('the bus moves on the map and the next stop advances', (
      tester,
    ) async {
      final sender = _FakeSender();
      final map = await _pumpTrip(
        tester,
        operations: FakeOperations(),
        sender: sender,
        trip: plannedTrip(),
        autoStart: true,
      );

      // At the terminal: next is "Centro" (10 min after the departure).
      sender.moveTo(10.4601, -84.0);
      await tester.pump();
      expect(map.buses.last?.latitude, 10.4601);
      expect(map.moves.last.lat, 10.4601); // the camera follows the bus
      expect(find.text('Centro'), findsOneWidget);
      final at = DateTime.utc(2026, 11, 11, 13, 10).toLocal();
      expect(
        find.text(
          'Próxima parada · Parada 2 de 3 · programada ${formatHour(at)}',
        ),
        findsOneWidget,
      );
      expect(map.highlighted?.name, 'Centro');

      // Past "Centro": next is "Muelle".
      sender.moveTo(10.4700, -84.0);
      await tester.pump();
      expect(find.text('Muelle'), findsOneWidget);

      // At the last stop.
      sender.moveTo(10.4800, -84.0);
      await tester.pump();
      expect(find.text('Llegaste a la última parada'), findsOneWidget);
    });

    testWidgets('"Ver ruta completa" stops following; "Centrar" resumes', (
      tester,
    ) async {
      final sender = _FakeSender();
      final map = await _pumpTrip(
        tester,
        operations: FakeOperations(),
        sender: sender,
        trip: plannedTrip(),
        autoStart: true,
      );
      sender.moveTo(10.4601, -84.0);
      await tester.pump();

      await tester.tap(find.byKey(const Key('fit-route')));
      await tester.pump();
      final moves = map.moves.length;
      final fits = map.fits.length;
      sender.moveTo(10.4650, -84.0);
      await tester.pump();
      expect(map.moves.length, moves); // not following
      expect(fits, greaterThan(1));

      await tester.tap(find.byKey(const Key('center-bus')));
      await tester.pump();
      expect(map.moves.last.lat, 10.4650);
    });

    testWidgets('no route in the trip: asks the Dashboard for the pattern', (
      tester,
    ) async {
      final operations = FakeOperations()
        ..patternById = pattern(
          patternId,
          stops: [
            stopAt('A', 10.46, -84.0, seq: 1),
            stopAt('B', 10.47, -84.0, seq: 2),
          ],
        );
      final map = await _pumpTrip(
        tester,
        operations: operations,
        sender: _FakeSender(),
        status: 'in_progress',
        autoStart: true,
      );
      await tester.pump();

      expect(operations.calls, contains('pattern $patternId'));
      expect(map.route?.stops.map((s) => s.name), ['A', 'B']);
    });

    testWidgets('no route anywhere: only the bus, with a note', (tester) async {
      final map = await _pumpTrip(
        tester,
        operations: FakeOperations(),
        sender: _FakeSender(),
        status: 'in_progress',
        autoStart: true,
      );
      await tester.pump();

      expect(map.route, isNull);
      expect(find.byKey(const Key('no-route-note')), findsOneWidget);
      expect(find.byKey(const Key('next-stop')), findsNothing);
      expect(find.text('Finalizar recorrido'), findsOneWidget);
    });

    testWidgets('compact panel fits a small phone without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final sender = _FakeSender();
      await _pumpTrip(
        tester,
        operations: FakeOperations(),
        sender: sender,
        trip: plannedTrip(),
        autoStart: true,
      );
      sender.moveTo(10.4601, -84.0);
      await tester.pump();

      expect(tester.takeException(), isNull);
      final map = tester.getSize(find.byKey(const Key('trip-map')));
      final panel = tester.getSize(find.byKey(const Key('trip-panel')));
      expect(map.height, greaterThan(panel.height)); // the map is the main part
    });
  });

  group('session expired (401)', () {
    testWidgets('GPS rejected with 401: clears the session, goes to Login', (
      tester,
    ) async {
      final sender = _FakeSender();
      await _pumpTrip(
        tester,
        operations: FakeOperations(),
        sender: sender,
        status: 'in_progress',
        autoStart: true,
      );

      sender.rejectSession();
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(
        find.text('Tu sesión expiró. Inicia sesión nuevamente.'),
        findsOneWidget,
      );
      expect(sender.stops, 1);
      expect(await SecureSessionStore().readToken(), isNull);
    });

    testWidgets('401 loading the trip in progress: goes to Login', (
      tester,
    ) async {
      await _pumpTrip(
        tester,
        operations: _UnauthorizedOperations(),
        sender: _FakeSender(),
      );
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(await SecureSessionStore().readToken(), isNull);
    });

    testWidgets('401 completing the trip: goes to Login', (tester) async {
      final sender = _FakeSender();
      await _pumpTrip(
        tester,
        operations: FakeOperations(completeError: ApiException.fromStatus(401)),
        sender: sender,
        status: 'in_progress',
        autoStart: true,
      );

      await tester.tap(find.text('Finalizar recorrido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finalizar'));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
    });
  });

  group('TripScreen', () {
    testWidgets('started trip: sends the GPS for that trip id, no POST', (
      tester,
    ) async {
      final operations = FakeOperations();
      final sender = _FakeSender();

      await _pumpTrip(
        tester,
        operations: operations,
        sender: sender,
        status: 'in_progress',
        autoStart: true,
      );

      // Home already started it.
      expect(operations.calls.where((c) => c.startsWith('start')), isEmpty);
      expect(sender.started, [tripId]);
      expect(_sending, findsOneWidget);
      expect(find.byKey(const Key('keep-app-open-notice')), findsOneWidget);
      // One line; a tap explains why.
      await tester.tap(find.byKey(const Key('keep-app-open-notice')));
      await tester.pumpAndSettle();
      expect(find.text(KeepAppOpenNotice.message), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.text('Finalizar recorrido'), findsOneWidget);
      expect(find.text('PV-RF · Puerto Viejo'), findsWidgets);
    });

    testWidgets('shows the backend start time in local time', (tester) async {
      final start = DateTime.utc(2026, 11, 11, 13, 5);
      await tester.pumpWidget(
        MaterialApp(
          home: TripScreen(
            trip: driverTrip(
              status: 'in_progress',
              actualDepartureAt: start.toIso8601String(),
            ),
            operations: FakeOperations(),
            sender: _FakeSender(),
            mapBuilder: _FakeMap().builder,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('Inició ${formatHour(start.toLocal())}'),
        findsOneWidget,
      );
    });

    testWidgets('scheduled trip: never starts it here, points to Home', (
      tester,
    ) async {
      final operations = FakeOperations();
      final sender = _FakeSender();

      await _pumpTrip(
        tester,
        operations: operations,
        sender: sender,
        status: 'scheduled',
        autoStart: true,
      );

      expect(operations.calls, isEmpty);
      expect(sender.started, isEmpty);
      expect(find.text('El viaje aún no ha iniciado'), findsOneWidget);
    });

    testWidgets('"Finalizar recorrido": stops the GPS and completes the trip', (
      tester,
    ) async {
      final operations = FakeOperations();
      final sender = _FakeSender();
      await _pumpTrip(
        tester,
        operations: operations,
        sender: sender,
        status: 'in_progress',
        autoStart: true,
      );

      await tester.tap(find.text('Finalizar recorrido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finalizar'));
      await tester.pumpAndSettle();

      expect(sender.stops, 1);
      expect(operations.calls.last, 'complete $tripId');
      expect(find.text('Recorrido finalizado'), findsOneWidget);
    });

    testWidgets('complete fails: offers to retry', (tester) async {
      final operations = FakeOperations(
        completeError: ApiException.noConnection,
      );
      final sender = _FakeSender();
      await _pumpTrip(
        tester,
        operations: operations,
        sender: sender,
        status: 'in_progress',
        autoStart: true,
      );

      await tester.tap(find.text('Finalizar recorrido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finalizar'));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo finalizar el viaje'), findsOneWidget);

      operations.completeError = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Recorrido finalizado'), findsOneWidget);
    });

    testWidgets('from the tab: picks up the trip in progress', (tester) async {
      final operations = FakeOperations(
        trips: [driverTrip(status: 'in_progress')],
      );
      final sender = _FakeSender();

      await _pumpTrip(tester, operations: operations, sender: sender);

      expect(operations.lastStatusFilter, TripStatus.inProgress);
      expect(find.text('Continuar recorrido'), findsOneWidget);
      expect(sender.started, isEmpty); // waits for the driver
    });

    testWidgets('from the tab, nothing in progress: points to Home', (
      tester,
    ) async {
      await _pumpTrip(
        tester,
        operations: FakeOperations(),
        sender: _FakeSender(),
      );

      expect(find.text('Sin recorrido en curso'), findsOneWidget);
      await tester.tap(find.text('Ir a Inicio'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });
  });
}

/// The Gateway answers 401 to the trips list.
class _UnauthorizedOperations extends FakeOperations {
  @override
  Future<List<DriverTrip>> driverTrips({
    DateTime? serviceDate,
    TripStatus? status,
  }) async => throw ApiException.fromStatus(401);
}
