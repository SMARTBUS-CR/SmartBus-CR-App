import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/buses_in_progress_screen.dart';
import 'package:smartbus_drivers/features/passenger/favorite_routes_screen.dart';
import 'package:smartbus_drivers/features/passenger/services/favorites_controller.dart';

import '../operations/operations_fixtures.dart';
import 'favorites_fakes.dart';

final _heredia = route('r-400', code: '400', name: 'Heredia – San José');
final _puerto = route('r-pv', code: 'PV-RF', name: 'Puerto Viejo');

late FakeFavoritesService _service;
late FavoritesController _favorites;

void _setUp({List<TransitRoute> saved = const []}) {
  _service = FakeFavoritesService(
    favorites: [
      for (final (i, r) in saved.indexed)
        favoriteOf(r, savedAt: DateTime(2026, 11, 1 + i), companyName: 'TUASA'),
    ],
  );
  _favorites = FavoritesController(service: _service);
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      routes: {'/login': (_) => const Scaffold(body: Text('login-screen'))},
      home: FavoriteRoutesScreen(
        favorites: _favorites,
        operations: FakeOperations(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The route detail with its star (where a passenger adds a favorite).
Future<void> _pumpRoute(WidgetTester tester, TransitRoute route) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RouteBusesScreen(
        route: route,
        operations: FakeOperations(),
        favorites: _favorites,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _star(TransitRoute route) =>
    find.byKey(Key('favorite-star-${route.id}'));

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'sb_access_token': 'token-1',
    }),
  );

  group('"Favoritos" tab', () {
    testWidgets('shows the bottom bar with "Favoritos" selected and no back', (
      tester,
    ) async {
      _setUp(saved: [_heredia]);
      await _pumpScreen(tester);

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 1);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Favoritos'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Volver'), findsNothing);
    });

    testWidgets('"Ver ruta" opens the home map with that route', (
      tester,
    ) async {
      _setUp(saved: [_puerto]);
      final operations = FakeOperations()
        ..patterns = [
          RoutePattern(id: 'p-ida', name: 'Ida', headsign: 'Río Frío'),
        ];
      Object? homeArgs;
      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteRoutesScreen(
            favorites: _favorites,
            operations: operations,
          ),
          onGenerateRoute: (settings) {
            if (settings.name != '/passenger/home') return null;
            homeArgs = settings.arguments;
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('home-map')),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Puerto Viejo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('show-route-p-ida')));
      await tester.pumpAndSettle();

      expect(find.text('home-map'), findsOneWidget);
      final selection = homeArgs! as RouteSelection;
      expect(selection.route.id, 'r-pv');
      expect(selection.pattern.id, 'p-ida');
    });
  });

  group('Mis favoritos', () {
    testWidgets('AC2 · asks the server and lists code, name and company, '
        'most recently saved first', (tester) async {
      _setUp(saved: [_heredia, _puerto]); // Puerto Viejo saved later
      await _pumpScreen(tester);

      expect(_service.calls, ['fetch']);
      expect(find.text('Mis favoritos'), findsOneWidget);
      final pv = tester.getTopLeft(find.text('Puerto Viejo')).dy;
      final hsj = tester.getTopLeft(find.text('Heredia – San José')).dy;
      expect(pv, lessThan(hsj));
      expect(find.text('400'), findsOneWidget);
      expect(find.text('TUASA'), findsNWidgets(2));
    });

    testWidgets('AC4 · empty state without error', (tester) async {
      _setUp();
      await _pumpScreen(tester);

      expect(find.byKey(const Key('favorites-empty')), findsOneWidget);
      expect(find.text('Aún no tienes rutas favoritas.'), findsOneWidget);
      expect(find.textContaining('estrella'), findsOneWidget);
      expect(find.byKey(const Key('favorites-error')), findsNothing);
    });

    testWidgets('AC9 · loading indicator, then 5xx with "Reintentar"', (
      tester,
    ) async {
      _setUp(saved: [_heredia]);
      _service.fetchError = const ApiException(
        ApiErrorType.serviceUnavailable,
        'El servicio no está disponible. Inténtalo nuevamente.',
      );
      _service.fetchGate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(home: FavoriteRoutesScreen(favorites: _favorites)),
      );
      await tester.pump();
      expect(find.byKey(const Key('favorites-loading')), findsOneWidget);

      _service.fetchGate!.complete();
      _service.fetchGate = null;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorites-error')), findsOneWidget);
      expect(find.textContaining('no está disponible'), findsOneWidget);

      _service.fetchError = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Heredia – San José'), findsOneWidget);
    });

    testWidgets('AC9 · 401 clears the session and opens login', (tester) async {
      _setUp();
      _service.fetchError = const ApiException(
        ApiErrorType.unauthorized,
        'Tu sesión expiró. Inicia sesión nuevamente.',
        statusCode: 401,
      );
      await _pumpScreen(tester);

      expect(find.text('login-screen'), findsOneWidget);
      expect(
        find.text('Tu sesión expiró. Inicia sesión nuevamente.'),
        findsOneWidget,
      );
      expect(await SecureSessionStore().readToken(), isNull);
    });

    testWidgets('AC6 · the star removes it at once; "Deshacer" saves it '
        'again', (tester) async {
      _setUp(saved: [_heredia, _puerto]);
      await _pumpScreen(tester);

      await tester.tap(_star(_heredia));
      await tester.pump();
      expect(find.text('Heredia – San José'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Ruta eliminada de favoritos.'), findsOneWidget);
      expect(_service.calls, contains('remove r-400'));

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(_service.calls.last, 'add r-400');
      expect(find.text('Heredia – San José'), findsOneWidget);
    });

    testWidgets('tapping a favorite opens the route, with its star filled', (
      tester,
    ) async {
      _setUp(saved: [_heredia]);
      await _pumpScreen(tester);

      await tester.tap(find.text('Heredia – San José'));
      await tester.pumpAndSettle();

      expect(find.byType(RouteBusesScreen), findsOneWidget);
      expect(find.text('En tus favoritos'), findsOneWidget);
    });

    testWidgets('AC6 · swiping an item removes it', (tester) async {
      _setUp(saved: [_heredia, _puerto]);
      await _pumpScreen(tester);

      await tester.drag(
        find.byKey(const Key('favorite-r-pv')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Puerto Viejo'), findsNothing);
      expect(_service.calls, contains('remove r-pv'));
      expect(find.text('Ruta eliminada de favoritos.'), findsOneWidget);
    });

    testWidgets('AC8 · a failed remove puts it back in its place', (
      tester,
    ) async {
      _setUp(saved: [_heredia, _puerto]);
      await _pumpScreen(tester);
      _service.error = const ApiException(
        ApiErrorType.noConnection,
        'Sin conexión a Internet.',
      );

      await tester.tap(_star(_puerto));
      await tester.pumpAndSettle();

      expect(find.text('Puerto Viejo'), findsOneWidget);
      expect(find.text('Sin conexión a Internet.'), findsOneWidget);
      final pv = tester.getTopLeft(find.text('Puerto Viejo')).dy;
      final hsj = tester.getTopLeft(find.text('Heredia – San José')).dy;
      expect(pv, lessThan(hsj));
    });

    testWidgets('AC10 · long names are cut at 2 lines; no overflow on '
        '320 × 568', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final long = route(
        'r-long',
        code: 'SJ-PV-EXPRESO-9',
        name: 'San José – Puerto Viejo de Sarapiquí por Vara Blanca ' * 4,
      );
      _setUp(saved: [long]);
      await _pumpScreen(tester);

      final name = tester.widget<Text>(find.textContaining('Vara Blanca'));
      expect(name.maxLines, 2);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  });

  group('Star on a route', () {
    testWidgets('AC5 · fills at once, says so, and the route is in '
        '"Mis favoritos"', (tester) async {
      _setUp();
      _service.gate = Completer<void>();
      await _pumpRoute(tester, _heredia);

      expect(find.text('Guardar en favoritos'), findsOneWidget);
      await tester.tap(_star(_heredia));
      await tester.pump();

      // Filled before the server answers.
      expect(find.text('En tus favoritos'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);

      _service.gate!.complete();
      await tester.pumpAndSettle();
      expect(_service.calls, ['fetch', 'add r-400']);
      expect(find.text('Ruta agregada a favoritos.'), findsOneWidget);
      expect(_favorites.favorites!.single.route.name, 'Heredia – San José');
    });

    testWidgets('AC8 · repeated taps send one request; a failure puts the '
        'star back with the message', (tester) async {
      _setUp();
      _service.gate = Completer<void>();
      await _pumpRoute(tester, _heredia);

      await tester.tap(_star(_heredia));
      await tester.pump();
      await tester.tap(_star(_heredia));
      await tester.tap(_star(_heredia));
      await tester.pump();

      _service.error = const ApiException(
        ApiErrorType.tooManyRequests,
        'Demasiados intentos. Espera un momento e inténtalo de nuevo.',
      );
      _service.gate!.complete();
      await tester.pumpAndSettle();

      expect(_service.calls.where((c) => c.startsWith('add')), hasLength(1));
      expect(find.text('Guardar en favoritos'), findsOneWidget);
      expect(find.textContaining('Demasiados intentos'), findsOneWidget);
    });

    testWidgets('a route already saved shows the filled star', (tester) async {
      _setUp(saved: [_heredia]);
      await _pumpRoute(tester, _heredia);
      expect(find.text('En tus favoritos'), findsOneWidget);
    });
  });

  group('Shared state', () {
    test(
      'AC3 · another session drops the previous list and asks again',
      () async {
        _setUp(saved: [_heredia]);
        await _favorites.load();
        expect(_favorites.isFavorite('r-400'), isTrue);

        // Log out and in with another account.
        FlutterSecureStorage.setMockInitialValues({
          'sb_access_token': 'token-2',
        });
        _service.stored.clear();
        await _favorites.load();

        expect(_favorites.isFavorite('r-400'), isFalse);
        expect(_service.calls, ['fetch', 'fetch']);
      },
    );

    test('load without force asks once per session', () async {
      _setUp(saved: [_heredia]);
      await _favorites.load();
      await _favorites.load();
      expect(_service.calls, ['fetch']);
      await _favorites.load(force: true);
      expect(_service.calls, ['fetch', 'fetch']);
    });
  });
}
