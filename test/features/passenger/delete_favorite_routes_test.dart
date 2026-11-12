import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/favorite_routes_screen.dart';
import 'package:smartbus_drivers/features/passenger/services/favorites_controller.dart';

import '../operations/operations_fixtures.dart';
import 'favorites_fakes.dart';

final _a = route('r-a', code: 'A1', name: 'Alajuela – San José');
final _b = route('r-b', code: 'B2', name: 'Barva – Heredia');
final _c = route('r-c', code: 'C3', name: 'Cartago – Tres Ríos');

late FakeFavoritesService _service;
late FavoritesController _favorites;

/// [saved] in list order (first = most recent). [_a] has the alias "Trabajo".
void _setUp([List<TransitRoute>? saved]) {
  final routes = saved ?? [_a, _b, _c];
  _service = FakeFavoritesService(
    favorites: [
      for (final (i, r) in routes.indexed)
        favoriteOf(
          r,
          savedAt: DateTime(2026, 11, 30 - i),
          label: r == _a ? 'Trabajo' : null,
        ),
    ],
  );
  _favorites = FavoritesController(service: _service);
}

List<String> get _listIds => [
  for (final f in _favorites.favorites ?? const []) f.routeId,
];

Future<void> _pump(WidgetTester tester) async {
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

Future<void> _edit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('favorites-edit')));
  await tester.pumpAndSettle();
}

Future<void> _check(WidgetTester tester, TransitRoute route) async {
  await tester.tap(find.byKey(Key('favorite-check-${route.id}')));
  await tester.pump();
}

/// "Eliminar (N)" → "Eliminar" in the dialog.
Future<void> _deleteSelected(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('delete-selected')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('delete-favorites-confirm')));
  await tester.pumpAndSettle();
}

FilledButton _deleteButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('delete-selected')));

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'sb_access_token': 'token-1',
    }),
  );

  group('FavoritesController.removeMany / restore', () {
    test(
      'removes at once, one DELETE per route, at most 4 at a time',
      () async {
        final routes = [
          for (var i = 0; i < 7; i++)
            route('r-$i', code: '$i', name: 'Ruta $i'),
        ];
        _setUp(routes);
        await _favorites.load();

        final removing = _favorites.removeMany([for (final r in routes) r.id]);
        expect(_favorites.favorites, isEmpty); // before the server answers
        final result = await removing;

        expect(result.removed, hasLength(7));
        expect(result.failed, isEmpty);
        expect(
          _service.calls.where((c) => c.startsWith('remove')),
          hasLength(7),
        );
        expect(_service.maxInFlight, FavoritesController.maxParallelRequests);
      },
    );

    test('partial failure: the failed routes go back to their place', () async {
      _setUp();
      await _favorites.load();
      _service.failingRoutes.add('r-b');

      final result = await _favorites.removeMany(['r-a', 'r-b', 'r-c']);

      expect(_listIds, ['r-b']);
      expect([for (final f in result.failed) f.routeId], ['r-b']);
      expect([for (final f in result.removed) f.routeId], ['r-a', 'r-c']);
      expect(result.error?.type, ApiErrorType.noConnection);
    });

    test('a failed route goes back between the ones that stayed', () async {
      _setUp();
      await _favorites.load();
      _service.failingRoutes.add('r-b');

      await _favorites.removeMany(['r-b']);

      expect(_listIds, ['r-a', 'r-b', 'r-c']);
    });

    test('each route is sent at most once, even if asked twice', () async {
      _setUp();
      await _favorites.load();
      _service.gate = Completer<void>();

      final first = _favorites.removeMany(['r-a', 'r-b']);
      final second = await _favorites.removeMany(['r-a', 'r-b']);
      expect(second.nothingSent, isTrue);
      _service.gate!.complete();
      await first;

      expect(_service.calls.where((c) => c == 'remove r-a'), hasLength(1));
      expect(_service.calls.where((c) => c == 'remove r-b'), hasLength(1));
    });

    test('a 401 is the error reported', () async {
      _setUp();
      await _favorites.load();
      _service.failingRoutes.addAll(['r-a', 'r-b']);
      _service.failure = const ApiException(
        ApiErrorType.unauthorized,
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );

      final result = await _favorites.removeMany(['r-a', 'r-b']);
      expect(result.error?.type, ApiErrorType.unauthorized);
    });

    test(
      'restore puts them back in their previous order, with their alias',
      () async {
        _setUp();
        await _favorites.load();
        final removal = await _favorites.removeMany(['r-a', 'r-c']);
        expect(_listIds, ['r-b']);

        final restoring = _favorites.restore(removal);
        expect(_listIds, ['r-a', 'r-b', 'r-c']); // at once
        final result = await restoring;

        expect(result.failed, isEmpty);
        expect(_listIds, ['r-a', 'r-b', 'r-c']);
        expect(_service.calls, containsAll(['add r-a (Trabajo)', 'add r-c']));
        expect(_favorites.favorites!.first.label, 'Trabajo');
      },
    );

    test('a restore that fails leaves those routes out again', () async {
      _setUp();
      await _favorites.load();
      final removal = await _favorites.removeMany(['r-a', 'r-c']);
      _service.failingRoutes.add('r-c');

      final result = await _favorites.restore(removal);

      expect(_listIds, ['r-a', 'r-b']);
      expect([for (final f in result.failed) f.routeId], ['r-c']);
    });
  });

  group('Mis favoritos · eliminar', () {
    testWidgets('AC1 · "Editar" shows checkboxes instead of stars and turns '
        'off swiping; "Listo" goes back without deleting', (tester) async {
      _setUp();
      await _pump(tester);

      await _edit(tester);
      expect(find.byKey(const Key('favorites-done')), findsOneWidget);
      expect(find.byKey(const Key('favorite-check-r-a')), findsOneWidget);
      expect(find.byKey(const Key('favorite-star-r-a')), findsNothing);

      await tester.drag(
        find.byKey(const Key('favorite-r-a')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alajuela – San José'), findsOneWidget);

      await tester.tap(find.byKey(const Key('favorites-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite-star-r-a')), findsOneWidget);
      expect(find.byKey(const Key('favorite-check-r-a')), findsNothing);
      expect(_service.calls, ['fetch']);
    });

    testWidgets('AC1 · Android back leaves edit mode first', (tester) async {
      _setUp();
      await _pump(tester);
      await _edit(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorites-edit')), findsOneWidget);
      expect(find.byType(FavoriteRoutesScreen), findsOneWidget);
    });

    testWidgets('AC2 · "Eliminar (N)" counts the selection, disabled at 0; '
        '"Seleccionar todo" selects / unselects all', (tester) async {
      _setUp();
      await _pump(tester);
      await _edit(tester);

      expect(find.text('Eliminar (0)'), findsOneWidget);
      expect(_deleteButton(tester).onPressed, isNull);

      await _check(tester, _a);
      await tester.tap(find.text('Barva – Heredia')); // the row toggles too
      await tester.pump();
      expect(find.text('Eliminar (2)'), findsOneWidget);
      expect(_deleteButton(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pump();
      expect(find.text('Eliminar (3)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pump();
      expect(find.text('Eliminar (0)'), findsOneWidget);
    });

    testWidgets('AC3 · confirmation: "Cancelar" keeps the selection; '
        '"Eliminar" removes them, closes edit mode and offers "Deshacer"', (
      tester,
    ) async {
      _setUp();
      await _pump(tester);
      await _edit(tester);
      await _check(tester, _a);
      await _check(tester, _c);

      await tester.tap(find.byKey(const Key('delete-selected')));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar 2 rutas de tus favoritos?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar (2)'), findsOneWidget);
      expect(_service.calls, ['fetch']);

      await _deleteSelected(tester);

      expect(_service.calls, containsAll(['remove r-a', 'remove r-c']));
      expect(find.text('Alajuela – San José'), findsNothing);
      expect(find.text('Cartago – Tres Ríos'), findsNothing);
      expect(find.text('Barva – Heredia'), findsOneWidget);
      expect(find.byKey(const Key('favorites-edit')), findsOneWidget);
      expect(find.text('2 rutas eliminadas de favoritos.'), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget);
    });

    testWidgets('AC4 · "Eliminar todos" (confirmed) leaves the empty state, '
        'without the option', (tester) async {
      _setUp();
      await _pump(tester);

      await tester.tap(find.byKey(const Key('favorites-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar todos'));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar todas tus rutas favoritas?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete-favorites-confirm')));
      await tester.pumpAndSettle();

      expect(_service.calls.where((c) => c.startsWith('remove')), hasLength(3));
      expect(find.text('Aún no tienes rutas favoritas.'), findsOneWidget);
      expect(find.byKey(const Key('favorites-menu')), findsNothing);
      expect(find.text('3 rutas eliminadas de favoritos.'), findsOneWidget);
    });

    testWidgets('AC5 · "Deshacer" saves them again in their previous order', (
      tester,
    ) async {
      _setUp();
      await _pump(tester);
      await _edit(tester);
      await _check(tester, _a);
      await _check(tester, _c);
      await _deleteSelected(tester);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();

      expect(_service.calls, containsAll(['add r-a (Trabajo)', 'add r-c']));
      final ya = tester.getTopLeft(find.text('Alajuela – San José')).dy;
      final yb = tester.getTopLeft(find.text('Barva – Heredia')).dy;
      final yc = tester.getTopLeft(find.text('Cartago – Tres Ríos')).dy;
      expect(ya < yb && yb < yc, isTrue);
    });

    testWidgets('AC6 · partial failure: the failed one comes back; '
        '"Reintentar" sends only that one', (tester) async {
      _setUp();
      await _pump(tester);
      _service.failingRoutes.add('r-b');

      await _edit(tester);
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pump();
      await _deleteSelected(tester);

      expect(find.text('Barva – Heredia'), findsOneWidget);
      expect(find.text('Alajuela – San José'), findsNothing);
      expect(
        find.textContaining('No se pudo eliminar 1 ruta.'),
        findsOneWidget,
      );

      _service.failingRoutes.clear();
      _service.calls.clear();
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(_service.calls, ['remove r-b']);
      expect(find.text('Aún no tienes rutas favoritas.'), findsOneWidget);
    });

    testWidgets('AC7 · while deleting, "Editar" and the menu do nothing', (
      tester,
    ) async {
      _setUp();
      await _pump(tester);
      _service.gate = Completer<void>();
      await _edit(tester);
      await _check(tester, _a);
      await _deleteSelected(tester);

      final edit = tester.widget<TextButton>(
        find.byKey(const Key('favorites-edit')),
      );
      expect(edit.onPressed, isNull);
      final menu = tester.widget<PopupMenuButton<void>>(
        find.byKey(const Key('favorites-menu')),
      );
      expect(menu.enabled, isFalse);

      _service.gate!.complete();
      await tester.pumpAndSettle();
      expect(_service.calls.where((c) => c == 'remove r-a'), hasLength(1));
    });

    testWidgets('AC8 · a 401 clears the session and opens login', (
      tester,
    ) async {
      _setUp();
      await _pump(tester);
      _service.failingRoutes.add('r-a');
      _service.failure = const ApiException(
        ApiErrorType.unauthorized,
        'Tu sesión expiró. Inicia sesión nuevamente.',
        statusCode: 401,
      );
      await _edit(tester);
      await _check(tester, _a);
      await _deleteSelected(tester);

      expect(find.text('login-screen'), findsOneWidget);
      expect(
        find.text('Tu sesión expiró. Inicia sesión nuevamente.'),
        findsOneWidget,
      );
      expect(await SecureSessionStore().readToken(), isNull);
    });

    testWidgets('AC9 · readable labels and no overflow on 320 × 568 in edit '
        'mode with long names', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();

      final long = route(
        'r-long',
        code: 'SJ-PV-EXPRESO-9',
        name: 'San José – Puerto Viejo de Sarapiquí por Vara Blanca ' * 4,
      );
      _setUp([long, _a, _b]);
      await _pump(tester);
      await _edit(tester);
      await _check(tester, long);
      await _check(tester, _a);

      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel('Eliminar 2 rutas seleccionadas'),
        findsOneWidget,
      );
      final name = tester.widget<Text>(find.textContaining('Vara Blanca'));
      expect(name.maxLines, 2);

      await tester.tap(find.byKey(const Key('delete-selected')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Cancelar'), findsOneWidget);
      handle.dispose();
    });
  });
}
