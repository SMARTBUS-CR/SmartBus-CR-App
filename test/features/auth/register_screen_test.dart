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
import 'package:smartbus_drivers/features/auth/register_screen.dart';
import 'package:smartbus_drivers/features/auth/services/auth_service.dart';

import 'auth_fixtures.dart';

// ---------------------------------------------------------------------------
// Test harness: RegisterScreen wired to a fake Gateway (MockClient).
// ---------------------------------------------------------------------------

typedef _Handler = Future<http.Response> Function(http.Request request);

final _name = find.byKey(const Key('register_name'));
final _email = find.byKey(const Key('register_email'));
final _password = find.byKey(const Key('register_password'));
final _confirm = find.byKey(const Key('register_password_confirmation'));
final _submit = find.byKey(const Key('register_submit'));

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Pumps the sign-up screen on top of a fake login, so "back" and the
/// post-sign-up navigation can be observed. Returns the sent requests.
Future<List<http.Request>> _pumpScreen(
  WidgetTester tester,
  _Handler handler,
) async {
  // Tall enough for the whole form without scrolling.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final requests = <http.Request>[];
  final store = SecureSessionStore();
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
      initialRoute: '/login',
      routes: {
        '/login': (_) => const Scaffold(body: Text('LOGIN')),
        '/register': (_) => RegisterScreen(authService: service),
        '/passenger/home': (_) => const Scaffold(body: Text('PASSENGER HOME')),
      },
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.pushNamed('/register');
  await tester.pumpAndSettle();

  return requests;
}

Future<void> _fillForm(
  WidgetTester tester, {
  String name = 'Ana Pérez',
  String email = 'ana@mail.com',
  String password = 'Secret#123',
  String? confirm,
}) async {
  await tester.enterText(_name, name);
  await tester.enterText(_email, email);
  await tester.enterText(_password, password);
  await tester.enterText(_confirm, confirm ?? password);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('AC1 · sign-up screen', () {
    testWidgets('shows the four fields and no role selector', (tester) async {
      await _pumpScreen(tester, (_) async => _json({}, 500));

      expect(_name, findsOneWidget);
      expect(_email, findsOneWidget);
      expect(_password, findsOneWidget);
      expect(_confirm, findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(Radio<String>), findsNothing);
    });

    testWidgets('"Inicia sesión" goes back to the login', (tester) async {
      await _pumpScreen(tester, (_) async => _json({}, 500));

      await tester.tap(
        find.textContaining('Inicia sesión', findRichText: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('LOGIN'), findsOneWidget);
    });
  });

  group('AC2 · client-side validation', () {
    testWidgets('empty form shows every error and sends nothing', (
      tester,
    ) async {
      final requests = await _pumpScreen(tester, (_) async => _json({}, 500));

      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text('Ingresa tu nombre'), findsOneWidget);
      expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
      expect(find.text('Ingresa una contraseña'), findsOneWidget);
      expect(find.text('Confirma tu contraseña'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('invalid email, weak password and mismatch', (tester) async {
      final requests = await _pumpScreen(tester, (_) async => _json({}, 500));

      await _fillForm(
        tester,
        email: 'ana@mail',
        password: 'secret',
        confirm: 'other',
      );
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
      expect(find.text('La contraseña no es segura'), findsOneWidget);
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('errors show while typing, before tapping "Crear cuenta"', (
      tester,
    ) async {
      final requests = await _pumpScreen(tester, (_) async => _json({}, 500));

      await tester.enterText(_email, 'ana@');
      await tester.pump();
      expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);

      await tester.enterText(_email, 'ana@mail.com');
      await tester.pump();
      expect(find.text('Ingresa un correo electrónico válido'), findsNothing);

      // Untouched fields do not show errors yet.
      expect(find.text('Ingresa tu nombre'), findsNothing);
      expect(requests, isEmpty);
    });

    testWidgets('requirements list appears while typing and checks rules', (
      tester,
    ) async {
      await _pumpScreen(tester, (_) async => _json({}, 500));

      const labels = [
        'Mínimo 8 caracteres',
        'Una letra mayúscula',
        'Una letra minúscula',
        'Un número',
        r'Un símbolo (ej. # ! @ $)',
      ];

      /// Icon next to a rule's label.
      IconData iconOf(String label) => tester
          .widget<Icon>(
            find.descendant(
              of: find
                  .ancestor(of: find.text(label), matching: find.byType(Row))
                  .first,
              matching: find.byType(Icon),
            ),
          )
          .icon!;

      // Hidden until the user starts typing.
      for (final label in labels) {
        expect(find.text(label), findsNothing);
      }

      await tester.enterText(_password, 'Abcdefgh');
      await tester.pumpAndSettle();
      expect(iconOf('Mínimo 8 caracteres'), Icons.check_circle);
      expect(iconOf('Una letra mayúscula'), Icons.check_circle);
      expect(iconOf('Una letra minúscula'), Icons.check_circle);
      expect(iconOf('Un número'), Icons.radio_button_unchecked);
      expect(iconOf(r'Un símbolo (ej. # ! @ $)'), Icons.radio_button_unchecked);

      // Listed top to bottom, in order.
      final ys = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
      expect(ys, orderedEquals([...ys]..sort()));

      await tester.enterText(_password, 'Secret#123');
      await tester.pumpAndSettle();
      for (final label in labels) {
        expect(iconOf(label), Icons.check_circle, reason: label);
      }
      expect(find.text('La contraseña no es segura'), findsNothing);
    });

    testWidgets('confirmation re-validates when the password changes', (
      tester,
    ) async {
      await _pumpScreen(tester, (_) async => _json({}, 500));

      final match = find.text('Las contraseñas coinciden');

      await tester.enterText(_password, 'Secret#123');
      await tester.enterText(_confirm, 'Secret#12');
      await tester.pump();
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(match, findsNothing);

      await tester.enterText(_confirm, 'Secret#123');
      await tester.pump();
      expect(find.text('Las contraseñas no coinciden'), findsNothing);
      expect(match, findsOneWidget);

      await tester.enterText(_password, 'Secret#1234');
      await tester.pump();
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(match, findsNothing);
    });

    testWidgets('name longer than 100 characters is rejected', (tester) async {
      final requests = await _pumpScreen(tester, (_) async => _json({}, 500));

      await _fillForm(tester, name: 'a' * 101);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(
        find.text('El nombre no puede superar 100 caracteres'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
    });
  });

  group('AC3 · loading state', () {
    testWidgets('disables the button and shows a spinner while sending', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      final requests = await _pumpScreen(tester, (_) => response.future);

      await _fillForm(tester);
      await tester.tap(_submit);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<ElevatedButton>(_submit).onPressed, isNull);

      // A second tap does not fire a second request.
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pump();
      expect(requests, hasLength(1));

      response.complete(
        _json(
          validationErrors({
            'email': ['x'],
          }),
          422,
        ),
      );
      await tester.pumpAndSettle();
    });
  });

  group('AC4 · successful sign-up (auto-login)', () {
    testWidgets('sends the payload without a role and opens passenger home', (
      tester,
    ) async {
      final requests = await _pumpScreen(
        tester,
        (_) async => _json(userDocument(token: 'new-token'), 201),
      );

      await _fillForm(tester, name: '  Ana Pérez  ', email: ' ana@mail.com ');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/auth/register/passenger'));
      expect(jsonDecode(request.body), {
        'name': 'Ana Pérez',
        'email': 'ana@mail.com',
        'password': 'Secret#123',
        'password_confirmation': 'Secret#123',
      });

      expect(find.text('PASSENGER HOME'), findsOneWidget);
      expect(find.textContaining('Cuenta creada'), findsOneWidget);
      expect(await SecureSessionStore().readToken(), 'new-token');

      // Back does not return to the sign-up (or the login).
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    });
  });

  group('AC5 · backend validation errors (422)', () {
    testWidgets('shows each message under its field and keeps the data', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        (_) async => _json(
          validationErrors({
            'email': ['El correo electrónico ya ha sido registrado.'],
            'password': ['La contraseña ha aparecido en una filtración.'],
          }),
          422,
        ),
      );

      await _fillForm(tester);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(
        find.text('El correo electrónico ya ha sido registrado.'),
        findsOneWidget,
      );
      expect(
        find.text('La contraseña ha aparecido en una filtración.'),
        findsOneWidget,
      );
      expect(find.text('ana@mail.com'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(_submit).onPressed, isNotNull);
      expect(await SecureSessionStore().readToken(), isNull);
    });

    testWidgets('editing a field clears its backend error', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => _json(
          validationErrors({
            'email': ['El correo electrónico ya ha sido registrado.'],
          }),
          422,
        ),
      );

      await _fillForm(tester);
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      await tester.enterText(_email, 'otra@mail.com');
      await tester.pumpAndSettle();

      expect(
        find.text('El correo electrónico ya ha sido registrado.'),
        findsNothing,
      );
    });
  });

  group('AC6 · network / server errors', () {
    testWidgets('no connection shows a SnackBar and re-enables the button', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        (_) async => throw const SocketException('offline'),
      );

      await _fillForm(tester);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión a Internet.'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(_submit).onPressed, isNotNull);
    });

    testWidgets('429 shows the throttling message', (tester) async {
      await _pumpScreen(
        tester,
        (_) async =>
            _json(jsonApiError(429, 'Too Many Requests', 'Too many'), 429),
      );

      await _fillForm(tester);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Demasiados intentos. Espera un momento e inténtalo de nuevo.',
        ),
        findsOneWidget,
      );
    });
  });
}
