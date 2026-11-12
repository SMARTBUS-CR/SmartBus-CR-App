import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/location/location_service.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/platform/notification_permission.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/driver/driver_home_screen.dart';
import 'package:smartbus_drivers/features/driver/trip_screen.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';

import '../operations/operations_fixtures.dart';

/// Location check without the device: answers [access], records the calls.
class _FakeLocation extends LocationService {
  _FakeLocation([this.access = LocationAccess.granted]);

  LocationAccess access;
  int checks = 0;
  final List<LocationAccess> openedSettings = [];

  @override
  Future<LocationAccess> checkAccess({bool request = true}) async {
    checks++;
    return access;
  }

  @override
  Future<void> openSettings(LocationAccess access) async {
    openedSettings.add(access);
  }
}

/// Android 13+ notification permission without the platform channel.
class _FakeNotifications extends NotificationPermission {
  bool allowed = true;
  int requests = 0;

  @override
  Future<bool> request() async {
    requests++;
    return allowed;
  }
}

class _Harness {
  _Harness(this.operations, {LocationAccess? access})
    : location = _FakeLocation(access ?? LocationAccess.granted);

  final FakeOperations operations;
  final _FakeLocation location;
  final _FakeNotifications notifications = _FakeNotifications();

  /// Arguments of every route pushed (the trip screen, login).
  final List<(String?, Object?)> opened = [];

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverHomeScreen(
          operations: operations,
          location: location,
          notifications: notifications,
          sessionStore: SecureSessionStore(),
          clock: () => DateTime(2026, 11, 11, 8),
        ),
        onGenerateRoute: (settings) {
          opened.add((settings.name, settings.arguments));
          return MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text('route ${settings.name}')),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  TripScreenArgs get tripArgs =>
      opened.singleWhere((r) => r.$1 == '/driver/trip').$2! as TripScreenArgs;
}

Finder _startButton([String id = tripId]) => find.byKey(Key('start-trip-$id'));

/// Taps "Iniciar recorrido" and confirms.
Future<void> _startAndConfirm(WidgetTester tester, [String id = tripId]) async {
  await tester.tap(_startButton(id));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-start')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({'sb_access_token': 'tok'}),
  );

  group('AC1 · assigned trips', () {
    testWidgets('loads today\'s trips with route, destination, bus, time', (
      tester,
    ) async {
      final operations = FakeOperations(
        trips: [
          DriverTrip.fromJsonApi(
            tripResource(withRelationships: true),
            included: JsonApiIncluded(driverTripsIncluded()),
          ),
        ],
      );
      await _Harness(operations).pump(tester);

      expect(operations.calls, ['driverTrips', 'driverTrips']);
      expect(find.text('PV-RF · Puerto Viejo'), findsOneWidget);
      expect(find.text('Hacia Puerto Viejo'), findsOneWidget);
      expect(find.text('Bus SJB-1234 · Unidad 07'), findsOneWidget);
      final departure = DateTime.utc(2026, 11, 11, 13).toLocal();
      final arrival = DateTime.utc(2026, 11, 11, 14).toLocal();
      expect(
        find.text(
          'Salida ${formatHour(departure)} · Llegada ${formatHour(arrival)}',
        ),
        findsOneWidget,
      );
      expect(find.text('Programado'), findsOneWidget);
    });

    testWidgets('no trips today', (tester) async {
      await _Harness(FakeOperations()).pump(tester);

      expect(find.text('No tienes viajes asignados para hoy.'), findsOneWidget);
    });

    testWidgets('a trip of another day still in progress shows first', (
      tester,
    ) async {
      await _Harness(
        FakeOperations(
          trips: [driverTrip(id: 'today-trip')],
          otherDayTrips: [driverTrip(id: 'old-trip', status: 'in_progress')],
        ),
      ).pump(tester);

      expect(
        tester.getTopLeft(find.byKey(const Key('trip-card-old-trip'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('trip-card-today-trip'))).dy,
        ),
      );
    });
  });

  group('AC2 · "Iniciar recorrido" button', () {
    testWidgets('only on scheduled trips', (tester) async {
      await _Harness(
        FakeOperations(
          trips: [
            driverTrip(id: 'a'),
            driverTrip(id: 'b', status: 'completed'),
            driverTrip(id: 'c', status: 'cancelled'),
          ],
        ),
      ).pump(tester);

      expect(_startButton('a'), findsOneWidget);
      expect(_startButton('b'), findsNothing);
      expect(_startButton('c'), findsNothing);
      expect(find.text('Iniciar recorrido'), findsOneWidget);
    });
  });

  group('AC3 / AC4 · successful start', () {
    testWidgets('confirm → POST start → trip screen with the started trip', (
      tester,
    ) async {
      final operations = FakeOperations(trips: [driverTrip()]);
      final h = _Harness(operations);
      await h.pump(tester);

      await _startAndConfirm(tester);

      expect(h.location.checks, 1);
      expect(operations.calls.last, 'start $tripId');
      final args = h.tripArgs;
      expect(args.trip.id, tripId);
      expect(args.trip.status, TripStatus.inProgress);
      // The backend's actual departure travels with the trip.
      expect(
        args.trip.actualDepartureAt?.toUtc(),
        DateTime.utc(2026, 11, 11, 13, 5),
      );
      expect(args.autoStart, isTrue); // the trip screen sends the GPS
    });

    testWidgets('the confirmation warns not to close the app', (tester) async {
      await _Harness(FakeOperations(trips: [driverTrip()])).pump(tester);

      await tester.tap(_startButton());
      await tester.pumpAndSettle();

      expect(find.text(KeepAppOpenNotice.title), findsOneWidget);
    });

    testWidgets('asks for notifications; a denial does not block the start', (
      tester,
    ) async {
      final h = _Harness(FakeOperations(trips: [driverTrip()]));
      h.notifications.allowed = false;
      await h.pump(tester);

      await _startAndConfirm(tester);

      expect(h.notifications.requests, 1);
      expect(h.operations.calls.last, 'start $tripId');
      expect(h.tripArgs.trip.id, tripId);
    });

    testWidgets('cancelling the confirmation does nothing', (tester) async {
      final operations = FakeOperations(trips: [driverTrip()]);
      final h = _Harness(operations);
      await h.pump(tester);

      await tester.tap(_startButton());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-start-dialog')), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(h.location.checks, 0);
      expect(operations.calls, isNot(contains('start $tripId')));
      expect(h.opened, isEmpty);
    });
  });

  group('AC5 · only one active trip', () {
    testWidgets('with a trip in progress: "Continuar", no other start', (
      tester,
    ) async {
      final h = _Harness(
        FakeOperations(
          trips: [
            driverTrip(
              id: 'active',
              status: 'in_progress',
              actualDepartureAt: '2026-11-11T13:05:00.000000Z',
            ),
            driverTrip(id: 'next'),
          ],
        ),
      );
      await h.pump(tester);

      expect(find.text('Iniciar recorrido'), findsNothing);
      expect(find.byKey(const Key('trip-blocked-next')), findsOneWidget);
      expect(
        find.text(
          'Inició a las '
          '${formatHour(DateTime.utc(2026, 11, 11, 13, 5).toLocal())}',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('continue-trip-active')));
      await tester.pumpAndSettle();

      expect(h.tripArgs.trip.id, 'active');
      expect(h.tripArgs.autoStart, isTrue);
      expect(h.operations.calls, isNot(contains('start active')));
    });

    testWidgets('a 422 "another trip in progress" shows its message', (
      tester,
    ) async {
      final operations = FakeOperations(
        trips: [driverTrip()],
        startError: const ApiException(
          ApiErrorType.validation,
          'The driver already has a trip in progress.',
        ),
      );
      final h = _Harness(operations);
      await h.pump(tester);

      await _startAndConfirm(tester);

      expect(
        find.text('The driver already has a trip in progress.'),
        findsOneWidget,
      );
      expect(h.opened, isEmpty);
    });
  });

  group('AC6 · location permission', () {
    for (final (access, message) in [
      (
        LocationAccess.denied,
        'Permite el acceso a tu ubicación para iniciar el recorrido.',
      ),
      (
        LocationAccess.deniedForever,
        'Permite el acceso a tu ubicación desde los ajustes de la app para '
            'iniciar el recorrido.',
      ),
      (
        LocationAccess.serviceDisabled,
        'Activa la ubicación (GPS) del dispositivo para iniciar el recorrido.',
      ),
    ]) {
      testWidgets('$access: the trip is NOT started', (tester) async {
        final operations = FakeOperations(trips: [driverTrip()]);
        final h = _Harness(operations, access: access);
        await h.pump(tester);

        await _startAndConfirm(tester);

        expect(operations.calls, isNot(contains('start $tripId')));
        expect(h.opened, isEmpty);
        expect(find.text(message), findsOneWidget);
        expect(h.notifications.requests, 0); // only after the location is ok
      });
    }

    testWidgets('location off: "Activar" opens the location settings', (
      tester,
    ) async {
      final h = _Harness(
        FakeOperations(trips: [driverTrip()]),
        access: LocationAccess.serviceDisabled,
      );
      await h.pump(tester);

      await _startAndConfirm(tester);
      await tester.tap(find.text('Activar'));
      await tester.pump();

      expect(h.location.openedSettings, [LocationAccess.serviceDisabled]);
    });

    testWidgets('permission denied: "Permitir" asks again and starts', (
      tester,
    ) async {
      final h = _Harness(
        FakeOperations(trips: [driverTrip()]),
        access: LocationAccess.denied,
      );
      await h.pump(tester);
      await _startAndConfirm(tester);

      h.location.access = LocationAccess.granted;
      await tester.tap(find.text('Permitir'));
      await tester.pumpAndSettle();

      expect(h.location.checks, 2);
      expect(h.operations.calls.last, 'start $tripId');
      expect(h.tripArgs.trip.id, tripId);
    });
  });

  group('AC7 / AC8 · start rejected', () {
    testWidgets('409: backend message, the list is refreshed, no GPS', (
      tester,
    ) async {
      final operations = FakeOperations(
        trips: [driverTrip()],
        startError: const ApiException(
          ApiErrorType.conflict,
          'Only scheduled trips can be started.',
        ),
      );
      final h = _Harness(operations);
      await h.pump(tester);

      await _startAndConfirm(tester);

      expect(find.text('Only scheduled trips can be started.'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      // Initial load (2 requests) + refresh after the error (2 more).
      expect(operations.calls.where((c) => c == 'driverTrips').length, 4);
      expect(h.opened, isEmpty);
    });

    for (final type in [ApiErrorType.forbidden, ApiErrorType.notFound]) {
      testWidgets('$type: "No puedes iniciar este viaje." and refresh', (
        tester,
      ) async {
        final operations = FakeOperations(
          trips: [driverTrip()],
          startError: ApiException(type, 'x'),
        );
        final h = _Harness(operations);
        await h.pump(tester);

        await _startAndConfirm(tester);

        expect(find.text('No puedes iniciar este viaje.'), findsOneWidget);
        expect(operations.calls.where((c) => c == 'driverTrips').length, 4);
        expect(h.opened, isEmpty);
      });
    }
  });

  group('AC9 · loading, session and network', () {
    testWidgets('spinner and disabled button while starting', (tester) async {
      final operations = FakeOperations(trips: [driverTrip()])
        ..startGate = Completer<void>();
      final h = _Harness(operations);
      await h.pump(tester);

      await tester.tap(_startButton());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-start')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('start-trip-spinner')), findsOneWidget);
      expect(find.text('Iniciando…'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(_startButton());
      expect(button.onPressed, isNull); // no double start

      operations.startGate!.complete();
      await tester.pumpAndSettle();
      expect(operations.calls.where((c) => c.startsWith('start')).length, 1);
      expect(h.tripArgs.trip.id, tripId);
    });

    testWidgets('401: clears the session and goes to Login', (tester) async {
      final operations = FakeOperations(
        trips: [driverTrip()],
        startError: ApiException.fromStatus(401),
      );
      final h = _Harness(operations);
      await h.pump(tester);

      await _startAndConfirm(tester);

      expect(h.opened.single.$1, '/login');
      expect(
        find.text('Tu sesión expiró. Inicia sesión nuevamente.'),
        findsOneWidget,
      );
      expect(await SecureSessionStore().readToken(), isNull);
    });

    testWidgets('401 while loading the trips also goes to Login', (
      tester,
    ) async {
      final operations = _UnauthorizedOperations();
      final h = _Harness(operations);
      await h.pump(tester);

      expect(h.opened.single.$1, '/login');
      expect(await SecureSessionStore().readToken(), isNull);
    });

    for (final error in [
      ApiException.noConnection,
      ApiException.timeout,
      ApiException.fromStatus(429),
      ApiException.fromStatus(503),
    ]) {
      testWidgets('${error.type}: "Reintentar", trip stays scheduled', (
        tester,
      ) async {
        final operations = FakeOperations(
          trips: [driverTrip()],
          startError: error,
        );
        final h = _Harness(operations);
        await h.pump(tester);

        await _startAndConfirm(tester);

        expect(find.text(error.message), findsOneWidget);
        expect(find.widgetWithText(SnackBarAction, 'Reintentar'), findsOne);
        expect(h.opened, isEmpty);
        expect(find.text('Programado'), findsOneWidget);
        expect(_startButton(), findsOneWidget);

        // Retry once the network is back: starts without asking again.
        operations.startError = null;
        await tester.tap(find.widgetWithText(SnackBarAction, 'Reintentar'));
        await tester.pumpAndSettle();

        expect(h.tripArgs.trip.id, tripId);
      });
    }
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
