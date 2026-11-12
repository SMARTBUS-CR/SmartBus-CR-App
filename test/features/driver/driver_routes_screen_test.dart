import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/driver/driver_routes_screen.dart';
import 'package:smartbus_drivers/features/driver/trip_screen.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';

import '../operations/operations_fixtures.dart';

/// "Today" of the tests (local).
final _today = DateTime(2026, 11, 12, 9);

/// A trip of the history, leaving [daysAgo] days before [_today] at [hour].
DriverTrip _trip(
  String id,
  TripStatus status, {
  int daysAgo = 0,
  int hour = 8,
  bool started = false,
  bool arrived = false,
  String? bus,
}) {
  final departure = DateTime(
    _today.year,
    _today.month,
    _today.day - daysAgo,
    hour,
  );
  return DriverTrip(
    id: id,
    status: status,
    routeCode: 'PV-RF',
    routeName: 'Puerto Viejo',
    headsign: 'Terminal Puerto Viejo',
    busPlate: bus,
    scheduledDepartureAt: departure,
    scheduledArrivalAt: departure.add(const Duration(hours: 1)),
    actualDepartureAt: started || arrived
        ? departure.add(const Duration(minutes: 5))
        : null,
    actualArrivalAt: arrived
        ? departure.add(const Duration(hours: 1, minutes: 7))
        : null,
  );
}

Future<void> _pump(WidgetTester tester, FakeOperations operations) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DriverRoutesScreen(
        operations: operations,
        sessionStore: SecureSessionStore(),
        clock: () => _today,
      ),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Text(
            settings.name == '/driver/trip'
                ? 'trip ${(settings.arguments as TripScreenArgs).trip.id}'
                : '${settings.name}',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _card(String id) => find.byKey(Key('history-trip-$id'));

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({'sb_access_token': 'tok'}),
  );

  testWidgets('lists every assigned trip, most recent first, grouped by day, '
      'with its status and data', (tester) async {
    // Tall enough to build every card (the list is lazy).
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final operations = FakeOperations()
      ..historyPages = [
        [
          _trip('today', TripStatus.scheduled, hour: 15, bus: 'SJB-1234'),
          _trip('running', TripStatus.inProgress, hour: 8, started: true),
          _trip('yesterday', TripStatus.completed, daysAgo: 1, arrived: true),
          _trip('old', TripStatus.cancelled, daysAgo: 6),
        ],
      ];
    await _pump(tester, operations);

    expect(operations.calls, ['history 1']);
    expect(find.text('Mis Rutas'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    expect(find.text('vie 6 nov'), findsOneWidget);

    // Same order as the Dashboard sent them.
    final tops = [
      for (final id in ['today', 'running', 'yesterday', 'old'])
        tester.getTopLeft(_card(id)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));

    // Status badges (the same as Inicio).
    for (final (id, label) in [
      ('today', 'Programado'),
      ('running', 'En curso'),
      ('yesterday', 'Finalizado'),
      ('old', 'Cancelado'),
    ]) {
      expect(
        find.descendant(of: _card(id), matching: find.text(label)),
        findsOneWidget,
        reason: id,
      );
    }

    // Data: destination, bus, scheduled and actual times + duration.
    final today = _card('today');
    expect(
      find.descendant(
        of: today,
        matching: find.text('Hacia Terminal Puerto Viejo'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: today, matching: find.text('Bus SJB-1234')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: today, matching: find.text('15:00 → 16:00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: today, matching: find.text('Pendiente de iniciar')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _card('yesterday'),
        matching: find.text('08:05 → 09:07 · 1 h 02 min'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _card('running'), matching: find.text('Salió 08:05')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _card('old'),
        matching: find.text('Este viaje fue cancelado'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('only a trip in progress offers "Continuar recorrido", which '
      'opens Recorrido with it', (tester) async {
    final operations = FakeOperations()
      ..historyPages = [
        [
          _trip('running', TripStatus.inProgress, started: true),
          _trip('done', TripStatus.completed, daysAgo: 1, arrived: true),
        ],
      ];
    await _pump(tester, operations);

    expect(find.text('Continuar recorrido'), findsOneWidget);
    await tester.tap(find.byKey(const Key('continue-running')));
    await tester.pumpAndSettle();
    expect(find.text('trip running'), findsOneWidget);
  });

  testWidgets('status chips filter on the server', (tester) async {
    final operations = FakeOperations()
      ..historyPages = [
        [
          _trip('a', TripStatus.completed, arrived: true),
          _trip('b', TripStatus.cancelled, daysAgo: 1),
          _trip('c', TripStatus.completed, daysAgo: 2, arrived: true),
        ],
      ];
    await _pump(tester, operations);

    await tester.tap(find.byKey(const Key('filter-completed')));
    await tester.pump();
    expect(operations.calls.last, 'history 1 completed');
    expect(_card('a'), findsOneWidget);
    expect(_card('c'), findsOneWidget);
    expect(_card('b'), findsNothing);

    await tester.tap(find.byKey(const Key('filter-inProgress')));
    await tester.pump();
    expect(find.text('No hay viajes en curso.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filter-all')));
    await tester.pump();
    expect(operations.calls.last, 'history 1');
    expect(_card('b'), findsOneWidget);
  });

  testWidgets('"Cargar más" appends the next page', (tester) async {
    final operations = FakeOperations()
      ..historyPages = [
        [_trip('p1', TripStatus.completed, arrived: true)],
        [_trip('p2', TripStatus.completed, daysAgo: 3, arrived: true)],
      ];
    await _pump(tester, operations);

    expect(_card('p2'), findsNothing);
    await tester.tap(find.byKey(const Key('load-more')));
    await tester.pump();

    expect(operations.calls, ['history 1', 'history 2']);
    expect(_card('p1'), findsOneWidget);
    expect(_card('p2'), findsOneWidget);
    expect(find.byKey(const Key('load-more')), findsNothing); // last page
  });

  testWidgets('"Cargar más" failing keeps the list and offers "Reintentar"', (
    tester,
  ) async {
    final operations = FakeOperations()
      ..historyPages = [
        [_trip('p1', TripStatus.completed, arrived: true)],
        [_trip('p2', TripStatus.completed, daysAgo: 3, arrived: true)],
      ];
    await _pump(tester, operations);

    operations.historyError = ApiException.noConnection;
    await tester.tap(find.byKey(const Key('load-more')));
    await tester.pumpAndSettle(); // the SnackBar is fully shown
    expect(find.text(ApiException.noConnection.message), findsOneWidget);
    expect(_card('p1'), findsOneWidget);

    operations.historyError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(_card('p2'), findsOneWidget);
  });

  testWidgets('no trips: empty state', (tester) async {
    await _pump(tester, FakeOperations());

    expect(find.text(DriverRoutesScreen.emptyMessage), findsOneWidget);
  });

  testWidgets('spinner while loading', (tester) async {
    final operations = FakeOperations()..historyGate = Completer<void>();
    await _pump(tester, operations);

    expect(find.byKey(const Key('history-loading')), findsOneWidget);
    operations.historyGate!.complete();
    await tester.pump();
    expect(find.byKey(const Key('history-loading')), findsNothing);
  });

  testWidgets('loading fails: message and "Reintentar"', (tester) async {
    final operations = FakeOperations()
      ..historyError = ApiException.fromStatus(503)
      ..historyPages = [
        [_trip('a', TripStatus.completed, arrived: true)],
      ];
    await _pump(tester, operations);

    expect(find.text('No se pudo cargar el historial'), findsOneWidget);
    operations.historyError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(_card('a'), findsOneWidget);
  });

  testWidgets('pull to refresh asks again', (tester) async {
    final operations = FakeOperations()
      ..historyPages = [
        [_trip('a', TripStatus.completed, arrived: true)],
      ];
    await _pump(tester, operations);

    await tester.fling(_card('a'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(operations.calls, ['history 1', 'history 1']);
  });

  testWidgets('401: clears the session and goes to Login', (tester) async {
    final operations = FakeOperations()
      ..historyError = ApiException.fromStatus(401);
    await _pump(tester, operations);
    await tester.pumpAndSettle();

    expect(find.text('/login'), findsOneWidget);
    expect(await SecureSessionStore().readToken(), isNull);
  });

  testWidgets('fits a 320 × 568 phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final operations = FakeOperations()
      ..historyPages = [
        [
          _trip('a', TripStatus.inProgress, started: true, bus: 'SJB-1234'),
          _trip('b', TripStatus.completed, daysAgo: 400, arrived: true),
        ],
      ];
    await _pump(tester, operations);

    expect(tester.takeException(), isNull);
    expect(_card('a'), findsOneWidget);
  });

  test('dayLabel', () {
    expect(dayLabel(_today, _today), 'Hoy');
    expect(dayLabel(DateTime(2026, 11, 11, 23), _today), 'Ayer');
    expect(dayLabel(DateTime(2026, 11, 13), _today), 'Mañana');
    expect(dayLabel(DateTime(2026, 11, 2), _today), 'lun 2 nov');
    expect(dayLabel(DateTime(2025, 10, 8), _today), 'mié 8 oct 2025');
    expect(dayLabel(null, _today), 'Sin fecha');
  });
}
