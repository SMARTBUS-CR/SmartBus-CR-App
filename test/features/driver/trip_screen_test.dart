import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/driver/driver_home_screen.dart';
import 'package:smartbus_drivers/features/driver/trip_screen.dart';
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
}

Future<void> _pumpTrip(
  WidgetTester tester, {
  required FakeOperations operations,
  required _FakeSender sender,
  String? status,
  bool autoStart = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TripScreen(
        trip: status == null ? null : driverTrip(status: status),
        autoStart: autoStart,
        operations: operations,
        sender: sender,
      ),
      routes: {'/driver/home': (_) => const Scaffold(body: Text('home'))},
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('TripScreen', () {
    testWidgets('scheduled trip: starts it in the Dashboard, then sends GPS', (
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

      expect(operations.calls, ['start $tripId']);
      expect(sender.started, [tripId]);
      expect(find.text('Enviando ubicación'), findsOneWidget);
      expect(find.text('PV-RF · Puerto Viejo'), findsWidgets);
    });

    testWidgets('trip already in progress: resumes the GPS only', (
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

      expect(operations.calls, isEmpty);
      expect(sender.started, [tripId]);
    });

    testWidgets('Dashboard refuses to start: shows why, no GPS', (
      tester,
    ) async {
      final operations = FakeOperations(
        startError: const ApiException(
          ApiErrorType.conflict,
          'El viaje no se puede iniciar todavía.',
        ),
      );
      final sender = _FakeSender();

      await _pumpTrip(
        tester,
        operations: operations,
        sender: sender,
        status: 'scheduled',
        autoStart: true,
      );

      expect(sender.started, isEmpty);
      expect(
        find.text('El viaje no se puede iniciar todavía.'),
        findsOneWidget,
      );
      expect(find.text('Iniciar recorrido'), findsOneWidget);
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
      expect(operations.calls, ['complete $tripId']);
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

  group('DriverHomeScreen', () {
    Future<void> pumpHome(
      WidgetTester tester,
      FakeOperations operations,
      List<Object?> opened,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DriverHomeScreen(operations: operations),
          onGenerateRoute: (settings) {
            opened.add(settings.arguments);
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('trip-screen')),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists today\'s trips and opens the picked one', (
      tester,
    ) async {
      final opened = <Object?>[];
      await pumpHome(
        tester,
        FakeOperations(trips: [driverTrip(status: 'scheduled')]),
        opened,
      );

      expect(find.text('PV-RF · Puerto Viejo'), findsOneWidget);
      expect(find.text('Programado'), findsOneWidget);
      expect(find.text('Hacia Puerto Viejo'), findsOneWidget);

      await tester.tap(find.text('Iniciar recorrido'));
      await tester.pumpAndSettle();

      final args = opened.single as TripScreenArgs;
      expect(args.trip.id, tripId);
      expect(args.autoStart, isTrue);
      expect(find.text('trip-screen'), findsOneWidget);
    });

    testWidgets('a trip in progress offers to continue it', (tester) async {
      await pumpHome(
        tester,
        FakeOperations(trips: [driverTrip(status: 'in_progress')]),
        [],
      );

      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Continuar recorrido'), findsOneWidget);
    });

    testWidgets('a trip of another day still in progress shows first', (
      tester,
    ) async {
      await pumpHome(
        tester,
        FakeOperations(
          trips: [driverTrip(id: 'today-trip')],
          otherDayTrips: [driverTrip(id: 'old-trip', status: 'in_progress')],
        ),
        [],
      );

      expect(find.text('Continuar recorrido'), findsOneWidget);
      expect(find.text('Iniciar recorrido'), findsOneWidget);
      // The one in progress is on top.
      expect(
        tester.getTopLeft(find.text('Continuar recorrido')).dy,
        lessThan(tester.getTopLeft(find.text('Iniciar recorrido')).dy),
      );
    });

    testWidgets('no trips today', (tester) async {
      await pumpHome(tester, FakeOperations(), []);

      expect(find.text('No tienes viajes asignados hoy'), findsOneWidget);
    });
  });
}
