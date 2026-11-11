import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbus_drivers/core/network/api_client.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/auth/models/auth_user.dart';
import 'package:smartbus_drivers/features/auth/services/auth_service.dart';
import 'package:smartbus_drivers/features/passenger/change_password_screen.dart';

import '../auth/auth_fixtures.dart';

// ---------------------------------------------------------------------------
// Test harness: ChangePasswordScreen pushed over a fake profile, wired to a
// fake Gateway (MockClient).
// ---------------------------------------------------------------------------

typedef _Handler = Future<http.Response> Function(http.Request request);

final _current = find.byKey(const Key('change_password_current'));
final _new = find.byKey(const Key('change_password_new'));
final _confirm = find.byKey(const Key('change_password_confirm'));
final _save = find.byKey(const Key('change_password_save'));

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<List<http.Request>> _pumpScreen(
  WidgetTester tester,
  _Handler handler,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final requests = <http.Request>[];
  final store = SecureSessionStore();
  await store.saveToken('stored-token');
  await store.saveUser(AuthUser.fromJsonApi(userDocument()).toJson());

  final service = AuthService(
    client: ApiClient(
      sessionStore: store,
      httpClient: MockClient((request) async {
        requests.add(request);
        return handler(request);
      }),
    ),
    sessionStore: store,
  );

  await tester.pumpWidget(
    MaterialApp(
      initialRoute: '/account',
      routes: {
        '/account': (_) => const Scaffold(body: Text('ACCOUNT')),
        '/login': (_) => const Scaffold(body: Text('LOGIN')),
      },
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChangePasswordScreen(authService: service, sessionStore: store),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return requests;
}

Future<void> _fill(
  WidgetTester tester, {
  String current = 'Old#1234',
  String password = 'New#12345',
  String? confirm,
}) async {
  await tester.enterText(_current, current);
  await tester.enterText(_new, password);
  await tester.enterText(_confirm, confirm ?? password);
}

bool _obscured(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .obscureText;

ElevatedButton _button(WidgetTester tester) => tester.widget<ElevatedButton>(
  find.descendant(of: _save, matching: find.byType(ElevatedButton)),
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('AC7 · form', () {
    testWidgets('three obscured fields with show / hide', (tester) async {
      await _pumpScreen(tester, (_) async => _json({}, 500));

      for (final field in [_current, _new, _confirm]) {
        expect(_obscured(tester, field), isTrue);
      }

      await tester.tap(
        find.descendant(of: _current, matching: find.byType(IconButton)),
      );
      await tester.pump();
      expect(_obscured(tester, _current), isFalse);
    });

    testWidgets('empty form: errors and no request', (tester) async {
      final requests = await _pumpScreen(tester, (_) async => _json({}, 500));

      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('Ingresa tu contraseña actual'), findsOneWidget);
      expect(find.text('Ingresa la nueva contraseña'), findsOneWidget);
      expect(find.text('Confirma la nueva contraseña'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('weak password and mismatch: errors and no request', (
      tester,
    ) async {
      final requests = await _pumpScreen(tester, (_) async => _json({}, 500));

      await _fill(tester, password: 'secret', confirm: 'other');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('La contraseña no es segura'), findsOneWidget);
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('new password equal to the current one: error, no request', (
      tester,
    ) async {
      final requests = await _pumpScreen(tester, (_) async => _json({}, 500));

      await _fill(tester, current: 'Same#1234', password: 'Same#1234');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(
        find.text('La nueva contraseña debe ser distinta de la actual'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
    });
  });

  group('AC8 · successful change', () {
    testWidgets('PUT, backend message, back to the profile, still logged in', (
      tester,
    ) async {
      final requests = await _pumpScreen(
        tester,
        (_) async => _json(metaMessage('Contraseña actualizada.'), 200),
      );

      await _fill(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();

      final request = requests.single;
      expect(request.method, 'PUT');
      expect(request.url.path, endsWith('/auth/user/password'));
      expect(jsonDecode(request.body), {
        'current_password': 'Old#1234',
        'password': 'New#12345',
        'password_confirmation': 'New#12345',
      });
      expect(find.text('Contraseña actualizada.'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(await SecureSessionStore().readToken(), 'stored-token');
    });
  });

  group('AC9 · backend errors (422)', () {
    testWidgets('wrong current password under its field', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => _json(
          validationErrors({
            'current_password': ['La contraseña es incorrecta.'],
          }),
          422,
        ),
      );

      await _fill(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('La contraseña es incorrecta.'), findsOneWidget);
      expect(_button(tester).onPressed, isNotNull);
    });

    testWidgets('compromised password under the new password', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => _json(
          validationErrors({
            'password': ['La contraseña ha aparecido en una filtración.'],
          }),
          422,
        ),
      );

      await _fill(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(
        find.text('La contraseña ha aparecido en una filtración.'),
        findsOneWidget,
      );
    });
  });

  group('AC10 · loading, session and network', () {
    testWidgets('spinner and disabled button while saving', (tester) async {
      final response = Completer<http.Response>();
      final requests = await _pumpScreen(tester, (_) => response.future);

      await _fill(tester);
      await tester.tap(_save);
      await tester.pump();

      expect(
        find.descendant(
          of: _save,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(_button(tester).onPressed, isNull);
      await tester.tap(_save, warnIfMissed: false);
      await tester.pump();
      expect(requests, hasLength(1));

      response.complete(_json(metaMessage('ok'), 200));
      await tester.pumpAndSettle();
    });

    testWidgets('401: clears the session and goes to login', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => _json({'message': 'Invalid or expired token.'}, 401),
      );

      await _fill(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('LOGIN'), findsOneWidget);
      expect(await SecureSessionStore().hasSession(), isFalse);
    });

    testWidgets('no connection: SnackBar and the typed values are kept', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        (_) async => throw const SocketException('offline'),
      );

      await _fill(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión a Internet.'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: _new, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'New#12345',
      );
    });
  });
}
