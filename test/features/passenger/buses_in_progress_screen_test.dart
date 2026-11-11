import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/buses_in_progress_screen.dart';

import '../operations/operations_fixtures.dart';

Future<List<Object?>> _pump(
  WidgetTester tester,
  FakeOperations operations,
) async {
  final tracked = <Object?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: BusesInProgressScreen(operations: operations),
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
    final tracked = await _pump(tester, operations);

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

    await tester.tap(find.text('Ver ruta'));
    await tester.pumpAndSettle();

    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Centro'), findsOneWidget);
    expect(find.text('+12 min'), findsOneWidget);
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
