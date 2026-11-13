import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/passenger/route_search_screen.dart';

import '../operations/operations_fixtures.dart';

const _debounce = Duration(milliseconds: 400);

final _field = find.byKey(const Key('route-search-field'));
final _hint = find.byKey(const Key('route-search-hint'));
final _loading = find.byKey(const Key('route-search-loading'));
final _error = find.byKey(const Key('route-search-error'));
final _empty = find.byKey(const Key('route-search-empty'));
final _more = find.byKey(const Key('route-search-more'));

const _heredia = TransitRoute(
  id: 'r-400',
  code: '400',
  name: 'Heredia – San José',
  companyName: 'TUASA',
  destinations: ['Heredia', 'San José'],
);
const _barva = TransitRoute(id: 'r-401', code: '401', name: 'Heredia – Barva');

RoutePage _page(List<TransitRoute> routes, {bool hasMore = false}) =>
    RoutePage(routes: routes, hasMore: hasMore);

/// Pumps the screen; returns the arguments of the routes it opens.
Future<List<Object?>> _pump(
  WidgetTester tester,
  FakeOperations operations, {
  Size size = const Size(1080, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final opened = <Object?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: RouteSearchScreen(operations: operations),
      onGenerateRoute: (settings) {
        opened.add(settings.arguments);
        return MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Text('route ${settings.name}')),
        );
      },
    ),
  );
  await tester.pump();
  return opened;
}

/// Types [text] and waits for the debounce.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump(_debounce);
  await tester.pump();
}

FakeOperations _answering(RoutePage page) =>
    FakeOperations()..onSearch = (_, _) async => page;

void main() {
  group('AC1 · entry point', () {
    testWidgets('opens with the keyboard ready and a hint', (tester) async {
      await _pump(tester, FakeOperations());

      expect(find.text('Buscar ruta'), findsOneWidget);
      expect(tester.widget<TextField>(_field).autofocus, isTrue);
      // The field has the focus and the keyboard is open.
      final editable = tester.state<EditableTextState>(
        find.descendant(of: _field, matching: find.byType(EditableText)),
      );
      expect(editable.widget.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(_hint, findsOneWidget);
    });
  });

  group('AC2 · search by name or number', () {
    testWidgets('searches 400 ms after the last key', (tester) async {
      final operations = FakeOperations();
      await _pump(tester, operations);

      await tester.enterText(_field, 'her');
      await tester.pump(const Duration(milliseconds: 399));
      expect(operations.calls, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(operations.calls, ['search her 1']);
    });

    testWidgets('fast typing sends only the last text, trimmed', (
      tester,
    ) async {
      final operations = FakeOperations();
      await _pump(tester, operations);

      await tester.enterText(_field, 'he');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(_field, 'here');
      await tester.pump(const Duration(milliseconds: 200));
      await _type(tester, 'heredia ');

      expect(operations.calls, ['search heredia 1']);
    });

    testWidgets('fewer than 2 characters: no request', (tester) async {
      final operations = FakeOperations();
      await _pump(tester, operations);

      await _type(tester, 'h');
      await _type(tester, ' h ');

      expect(operations.calls, isEmpty);
      expect(_hint, findsOneWidget);
    });

    testWidgets('only the latest search is shown (older answers ignored)', (
      tester,
    ) async {
      final slow = Completer<RoutePage>();
      final operations = FakeOperations()
        ..onSearch = (query, _) =>
            query == 'he' ? slow.future : Future.value(_page([_barva]));
      await _pump(tester, operations);

      await _type(tester, 'he'); // slow answer
      await _type(tester, 'barva'); // fast answer
      expect(find.text('Heredia – Barva'), findsOneWidget);

      slow.complete(_page([_heredia]));
      await tester.pump();

      expect(find.text('Heredia – Barva'), findsOneWidget);
      expect(find.text('Heredia – San José'), findsNothing);
    });
  });

  group('AC4 · results', () {
    testWidgets('code badge, name, company and destinations', (tester) async {
      await _pump(tester, _answering(_page([_heredia, _barva])));

      await _type(tester, 'heredia');

      expect(find.text('400'), findsOneWidget);
      expect(find.text('Heredia – San José'), findsOneWidget);
      expect(find.text('TUASA · Hacia Heredia, San José'), findsOneWidget);
      expect(find.text('401'), findsOneWidget);
      // A route without company or destinations shows no details line.
      expect(find.byKey(const Key('route-result-details')), findsOneWidget);
    });

    testWidgets('the typed text is highlighted in the name', (tester) async {
      await _pump(tester, _answering(_page([_heredia])));

      await _type(tester, 'SAN');

      final name = tester.widget<Text>(
        find.byKey(const Key('route-result-name')),
      );
      final spans = name.textSpan!.toPlainText();
      expect(spans, 'Heredia – San José');
      final bold = <String>[];
      name.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.style?.fontWeight == FontWeight.bold) {
          bold.add(span.text!);
        }
        return true;
      });
      expect(bold, ['San']);
    });

    testWidgets('"Cargar más" appends the next page', (tester) async {
      final operations = FakeOperations()
        ..onSearch = (_, page) async => page == 1
            ? _page([_heredia], hasMore: true)
            : _page([_heredia, _barva]); // repeated route is skipped
      await _pump(tester, operations);

      await _type(tester, 'heredia');
      expect(find.text('Cargar más'), findsOneWidget);

      await tester.tap(_more);
      await tester.pump();

      expect(operations.calls, ['search heredia 1', 'search heredia 2']);
      expect(find.text('Heredia – San José'), findsOneWidget);
      expect(find.text('Heredia – Barva'), findsOneWidget);
      expect(_more, findsNothing); // last page
    });

    testWidgets('"Cargar más" failing keeps the results and offers retry', (
      tester,
    ) async {
      var failed = false;
      final operations = FakeOperations()
        ..onSearch = (_, page) async {
          if (page == 1) return _page([_heredia], hasMore: true);
          if (!failed) {
            failed = true;
            throw ApiException.noConnection;
          }
          return _page([_barva]);
        };
      await _pump(tester, operations);

      await _type(tester, 'heredia');
      await tester.tap(_more);
      await tester.pump();

      expect(find.text('Heredia – San José'), findsOneWidget);
      expect(find.byKey(const Key('route-search-more-error')), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();

      expect(find.text('Heredia – Barva'), findsOneWidget);
    });
  });

  group('AC5 · select a route', () {
    testWidgets('opens /passenger/route with the route', (tester) async {
      final opened = await _pump(tester, _answering(_page([_heredia])));

      await _type(tester, 'heredia');
      await tester.tap(find.text('Heredia – San José'));
      await tester.pumpAndSettle();

      expect(find.text('route /passenger/route'), findsOneWidget);
      expect(opened.single, isA<TransitRoute>());
      expect((opened.single! as TransitRoute).id, 'r-400');
    });

    // The route detail: its "Ver ruta" answers with the direction to draw.
    final selection = RouteSelection(
      route: _heredia,
      pattern: pattern('p-400', headsign: 'San José', stops: const []),
    );
    Route<Object?> detail(RouteSettings settings) => MaterialPageRoute<Object?>(
      settings: settings,
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.pop(context, selection),
          child: const Text('Ver ruta'),
        ),
      ),
    );

    testWidgets('"Ver ruta" in the detail closes the search and hands the '
        'route to the map that opened it', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      Object? backOnMap;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  backOnMap = await Navigator.push<Object?>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RouteSearchScreen(
                        operations: _answering(_page([_heredia])),
                      ),
                    ),
                  );
                },
                child: const Text('map'),
              ),
            ),
          ),
          onGenerateRoute: detail,
        ),
      );
      await tester.tap(find.text('map'));
      await tester.pumpAndSettle();
      await _type(tester, 'heredia');
      await tester.tap(find.text('Heredia – San José'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver ruta'));
      await tester.pumpAndSettle();

      expect(backOnMap, same(selection));
      expect(find.byType(RouteSearchScreen), findsNothing);
      expect(find.text('map'), findsOneWidget);
    });

    testWidgets(
      'as the first screen, "Ver ruta" opens the map with the route',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.75;
        addTearDown(tester.view.reset);
        final homeArgs = <Object?>[];
        await tester.pumpWidget(
          MaterialApp(
            home: RouteSearchScreen(operations: _answering(_page([_heredia]))),
            onGenerateRoute: (settings) {
              if (settings.name != '/passenger/home') return detail(settings);
              homeArgs.add(settings.arguments);
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('home-map')),
              );
            },
          ),
        );
        await tester.pump();
        await _type(tester, 'heredia');
        await tester.tap(find.text('Heredia – San José'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ver ruta'));
        await tester.pumpAndSettle();

        expect(find.text('home-map'), findsOneWidget);
        expect(homeArgs.single, same(selection));
        expect(find.byType(RouteSearchScreen), findsNothing);
      },
    );

    testWidgets('back from the detail (no "Ver ruta") stays on the search', (
      tester,
    ) async {
      await _pump(tester, _answering(_page([_heredia])));
      await _type(tester, 'heredia');
      await tester.tap(find.text('Heredia – San José'));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byType(RouteSearchScreen), findsOneWidget);
      expect(find.text('Heredia – San José'), findsOneWidget);
    });
  });

  group('AC6 · no matches', () {
    testWidgets('informative message with the typed text', (tester) async {
      await _pump(tester, FakeOperations());

      await _type(tester, 'xyz');

      expect(_empty, findsOneWidget);
      expect(find.text('No encontramos rutas para "xyz".'), findsOneWidget);
      expect(
        find.text('Prueba con otro nombre, número o destino.'),
        findsOneWidget,
      );
    });
  });

  group('AC7 · clear', () {
    testWidgets('X clears the field and the results, without a request', (
      tester,
    ) async {
      final operations = _answering(_page([_heredia]));
      await _pump(tester, operations);

      await _type(tester, 'heredia');
      await tester.tap(find.byKey(const Key('route-search-clear')));
      await tester.pump(_debounce);

      expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
      expect(find.text('Heredia – San José'), findsNothing);
      expect(_hint, findsOneWidget);
      expect(operations.calls, ['search heredia 1']);
    });

    testWidgets('clearing drops an answer still on its way', (tester) async {
      final slow = Completer<RoutePage>();
      final operations = FakeOperations()..onSearch = (_, _) => slow.future;
      await _pump(tester, operations);

      await _type(tester, 'heredia');
      await tester.tap(find.byKey(const Key('route-search-clear')));
      await tester.pump();
      slow.complete(_page([_heredia]));
      await tester.pump();

      expect(find.text('Heredia – San José'), findsNothing);
      expect(_hint, findsOneWidget);
    });
  });

  group('AC8 · loading and errors', () {
    testWidgets('shows a spinner while searching and keeps the text', (
      tester,
    ) async {
      final answer = Completer<RoutePage>();
      final operations = FakeOperations()..onSearch = (_, _) => answer.future;
      await _pump(tester, operations);

      await _type(tester, 'heredia');

      expect(_loading, findsOneWidget);
      expect(tester.widget<TextField>(_field).controller!.text, 'heredia');

      answer.complete(_page([_heredia]));
      await tester.pump();
      expect(_loading, findsNothing);
    });

    for (final (name, error) in [
      ('no connection', ApiException.noConnection),
      ('timeout', ApiException.timeout),
      ('429', ApiException.fromStatus(429)),
      ('503', ApiException.fromStatus(503)),
    ]) {
      testWidgets('$name: message and "Reintentar" repeats the search', (
        tester,
      ) async {
        var failed = false;
        final operations = FakeOperations()
          ..onSearch = (_, _) async {
            if (!failed) {
              failed = true;
              throw error;
            }
            return _page([_heredia]);
          };
        await _pump(tester, operations);

        await _type(tester, 'heredia');

        expect(_error, findsOneWidget);
        expect(find.text(error.message), findsOneWidget);
        expect(tester.widget<TextField>(_field).controller!.text, 'heredia');

        await tester.tap(find.text('Reintentar'));
        await tester.pump();

        expect(operations.calls, ['search heredia 1', 'search heredia 1']);
        expect(_error, findsNothing);
        expect(find.text('Heredia – San José'), findsOneWidget);
      });
    }
  });

  group('AC9 · long text and small screens', () {
    testWidgets('long names and destinations do not overflow on 320 × 568', (
      tester,
    ) async {
      final long = TransitRoute(
        id: 'r-long',
        code: 'CODIGO-MUY-LARGO-123',
        name: 'Ruta ${'muy larga ' * 20}',
        companyName: 'Empresa de Transportes ${'Unidos ' * 10}',
        destinations: [for (var i = 0; i < 8; i++) 'Destino lejano $i'],
      );
      // 320 × 568 logical pixels at the harness' 2.75 ratio.
      await _pump(
        tester,
        _answering(_page([long, _heredia], hasMore: true)),
        size: const Size(880, 1562),
      );

      await _type(tester, 'ruta');

      expect(tester.takeException(), isNull);
      for (final key in ['route-result-name', 'route-result-details']) {
        final text = tester.widget<Text>(find.byKey(Key(key)).first);
        expect(text.maxLines, 2, reason: key);
        expect(text.overflow, TextOverflow.ellipsis, reason: key);
      }
      final code = tester.widget<Text>(
        find.byKey(const Key('route-result-code')).first,
      );
      expect(code.maxLines, 1);
    });
  });

  group('highlightMatch', () {
    const base = TextStyle();
    const bold = TextStyle(fontWeight: FontWeight.bold);

    List<String?> boldParts(TextSpan span) => [
      for (final child in span.children ?? const <InlineSpan>[])
        if (child is TextSpan && child.style == bold) child.text,
    ];

    test('every case-insensitive occurrence', () {
      final span = highlightMatch('Heredia - heredia', 'HER', base, bold);
      expect(span.toPlainText(), 'Heredia - heredia');
      expect(boldParts(span), ['Her', 'her']);
    });

    test('with or without accents ("jose" highlights "José")', () {
      final span = highlightMatch('San José', 'jose', base, bold);
      expect(span.toPlainText(), 'San José');
      expect(boldParts(span), ['José']);

      expect(boldParts(highlightMatch('Peña', 'PENA', base, bold)), ['Peña']);
      expect(boldParts(highlightMatch('Heredia', 'heredía', base, bold)), [
        'Heredia',
      ]);
    });

    test('no match or empty query: plain text', () {
      expect(boldParts(highlightMatch('Barva', 'xyz', base, bold)), isEmpty);
      expect(highlightMatch('Barva', ' ', base, bold).toPlainText(), 'Barva');
    });
  });
}
