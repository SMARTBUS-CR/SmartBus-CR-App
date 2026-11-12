import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/buses_in_progress_screen.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/route_live_buses.dart';

import '../operations/operations_fixtures.dart';
import '../trip_tracking/trip_tracking_fakes.dart';

Future<List<Object?>> _pump(
  WidgetTester tester,
  FakeOperations operations, {
  FakeGps? gps,
}) async {
  final tracked = <Object?>[];
  final trackers = FakeTrackers(gps ?? FakeGps());
  await tester.pumpWidget(
    MaterialApp(
      home: BusesInProgressScreen(
        operations: operations,
        liveBusesFactory: (patternId) => RouteLiveBuses(
          patternId: patternId,
          operations: operations,
          trackerFactory: trackers.call,
        ),
      ),
      onGenerateRoute: (settings) {
        tracked.add(settings.arguments);
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('tracking-screen')),
        );
      },
    ),
  );
  await tester.pumpAndSettle();
  return tracked;
}

FakeOperations _withRoute({List<LiveBusTrip> buses = const []}) =>
    FakeOperations(
      routeList: [TransitRoute.fromJsonApi(routeResource())],
      patterns: [RoutePattern.fromJsonApi(patternResource())],
      buses: {patternId: buses},
    );

void main() {
  testWidgets('route -> buses running -> live tracking of the picked bus', (
    tester,
  ) async {
    final operations = _withRoute(
      buses: [LiveBusTrip.fromJsonApi(liveTripResource())],
    );
    final tracked = await _pump(
      tester,
      operations,
      gps: FakeGps({tripId: inProgressAt(tripId, 10.465, -83.985)}),
    );

    expect(find.text('Buses en curso'), findsOneWidget);
    await tester.tap(find.text('Puerto Viejo'));
    await tester.pumpAndSettle();

    expect(operations.calls, [
      'routes',
      'patterns $routeId',
      'buses $patternId',
    ]);
    expect(find.text('Hacia Puerto Viejo'), findsOneWidget);
    expect(find.text('Unidad 12 · ABC-123'), findsOneWidget);

    await tester.tap(find.text('Ver en vivo'));
    await tester.pumpAndSettle();

    expect(tracked.single, tripId);
    expect(find.text('tracking-screen'), findsOneWidget);
  });

  testWidgets('each bus shows its live status and where it is', (tester) async {
    final operations = _withRoute(
      buses: [LiveBusTrip.fromJsonApi(liveTripResource())],
    );
    // Between Terminal and Centro: Centro is the next stop.
    await _pump(
      tester,
      operations,
      gps: FakeGps({tripId: inProgressAt(tripId, 10.465, -83.985)}),
    );
    await tester.tap(find.text('Puerto Viejo'));
    await tester.pumpAndSettle();

    final status = tester.widget<Text>(
      find.byKey(const Key('bus-status-$tripId')),
    );
    expect(status.data, startsWith('En vivo'));
    expect(find.byKey(const Key('bus-next-stop-$tripId')), findsOneWidget);
    expect(find.text('Próxima parada: Centro'), findsOneWidget);
  });

  testWidgets('a bus without position yet: "Esperando ubicación", no stop', (
    tester,
  ) async {
    final operations = _withRoute(
      buses: [LiveBusTrip.fromJsonApi(liveTripResource())],
    );
    await _pump(
      tester,
      operations,
      gps: FakeGps({
        tripId: const TripTracking(
          tripId: tripId,
          status: TripStatus.inProgress,
          freshness: TrackingFreshness.noSignal,
        ),
      }),
    );
    await tester.tap(find.text('Puerto Viejo'));
    await tester.pumpAndSettle();

    expect(find.text('Esperando ubicación'), findsOneWidget);
    expect(find.byKey(const Key('bus-next-stop-$tripId')), findsNothing);
  });

  testWidgets('a trip the GPS service says finished is not listed', (
    tester,
  ) async {
    final operations = _withRoute(
      buses: [LiveBusTrip.fromJsonApi(liveTripResource())],
    );
    await _pump(
      tester,
      operations,
      gps: FakeGps({tripId: finishedTrip(tripId)}),
    );
    await tester.tap(find.text('Puerto Viejo'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bus-$tripId')), findsNothing);
    expect(
      find.text('No hay buses en curso en este recorrido.'),
      findsOneWidget,
    );
  });

  testWidgets('no buses running: says so, and the route can still be seen', (
    tester,
  ) async {
    await _pump(tester, _withRoute());
    await tester.tap(find.text('Puerto Viejo'));
    await tester.pumpAndSettle();

    expect(
      find.text('No hay buses en curso en este recorrido.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Ver paradas'));
    await tester.pumpAndSettle();

    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Centro'), findsOneWidget);
    expect(find.text('+12 min'), findsOneWidget);
  });

  testWidgets('"Ver ruta" closes both screens with the route and direction', (
    tester,
  ) async {
    final second = RoutePattern.fromJsonApi(patternResource());
    final operations = _withRoute()
      ..patterns = [
        RoutePattern.fromJsonApi(patternResource()),
        RoutePattern(
          id: 'p-back',
          name: 'Regreso',
          headsign: 'Río Frío',
          stops: second.stops,
        ),
      ];
    Object? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<Object?>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BusesInProgressScreen(operations: operations),
                  ),
                );
              },
              child: const Text('home-map'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('home-map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Puerto Viejo'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('show-route-p-back')));
    await tester.pumpAndSettle();

    // Back on the home map, with what to draw.
    expect(find.text('home-map'), findsOneWidget);
    final selection = result! as RouteSelection;
    expect(selection.route.id, routeId);
    expect(selection.pattern.id, 'p-back');
    // Every direction comes along, so the passenger can switch.
    expect(selection.route.patterns.map((p) => p.id), [patternId, 'p-back']);
  });

  testWidgets('routes fail to load: retry', (tester) async {
    final operations = _OnceFailing();
    await _pump(tester, operations);

    expect(find.text('No se pudieron cargar las rutas'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Puerto Viejo'), findsOneWidget);
  });
}

class _OnceFailing extends FakeOperations {
  _OnceFailing()
    : super(routeList: [TransitRoute.fromJsonApi(routeResource())]);

  bool _failed = false;

  @override
  Future<List<TransitRoute>> routes() async {
    if (!_failed) {
      _failed = true;
      throw ApiException.noConnection;
    }
    return super.routes();
  }
}
