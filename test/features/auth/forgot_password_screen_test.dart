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
import 'package:smartbus_drivers/features/auth/forgot_password_screen.dart';
import 'package:smartbus_drivers/features/auth/login_screen.dart';
import 'package:smartbus_drivers/features/auth/services/auth_service.dart';

import 'auth_fixtures.dart';

// ---------------------------------------------------------------------------
// Harness: the login screen + "Recuperar contraseña" on a fake Gateway.
// ---------------------------------------------------------------------------

typedef _Handler = Future<http.Response> Function(http.Request request);

const _email = 'ana@mail.com';
const _sent = 'Se ha enviado un código de recuperación a tu correo.';
const _done = 'Contraseña actualizada correctamente.';
const _strong = 'Nueva#Clave1';

final _emailField = find.byKey(const Key('forgot_email'));
final _send = find.byKey(const Key('forgot_send'));
final _code = find.byKey(const Key('forgot_code'));
final _password = find.byKey(const Key('forgot_password'));
final _confirm = find.descendant(
  of: find.byKey(const Key('forgot_password_confirmation')),
  matching: find.byType(TextFormField),
);
final _submit = find.byKey(const Key('forgot_submit'));
final _resend = find.byKey(const Key('forgot_resend'));

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Answers `forgot` with [forgot] and `reset` with [reset] (200 by default).
_Handler _gateway({
  Future<http.Response> Function()? forgot,
  Future<http.Response> Function()? reset,
}) => (request) async {
  if (request.url.path.endsWith('/password/forgot')) {
    return forgot?.call() ?? _json(metaMessage(_sent), 200);
  }
  if (request.url.path.endsWith('/password/reset')) {
    return reset?.call() ?? _json(metaMessage(_done), 200);
  }
  return _json(jsonApiError(404, 'Not Found', 'No route'), 404);
};

/// The login screen with the real route to `/forgot-password`. Returns the
/// requests sent to the Gateway.
Future<List<http.Request>> _pumpLogin(
  WidgetTester tester,
  _Handler handler, {
  Size size = const Size(1080, 2400),
  double ratio = 2.75,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
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
      home: LoginScreen(authService: service),
      onGenerateRoute: (settings) => settings.name == '/forgot-password'
          ? MaterialPageRoute<PasswordResetDone>(
              settings: settings,
              builder: (_) => ForgotPasswordScreen(
                initialEmail: settings.arguments as String?,
                authService: service,
              ),
            )
          : null,
    ),
  );
  return requests;
}

Future<void> _openForgot(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('login_forgot_password')));
  await tester.pumpAndSettle();
}

/// Step 1 with [email] → step 2.
Future<void> _requestCode(WidgetTester tester, {String email = _email}) async {
  await tester.enterText(_emailField, email);
  await tester.tap(_send);
  await tester.pumpAndSettle();
}

Future<void> _fillReset(
  WidgetTester tester, {
  String code = '123456',
  String password = _strong,
  String? confirm,
}) async {
  await tester.enterText(_code, code);
  await tester.enterText(_password, password);
  await tester.enterText(_confirm, confirm ?? password);
  await tester.pump();
}

Map<String, dynamic> _body(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

/// Disposes the screen so its cooldown timer does not outlive the test.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('AC1 · "¿Olvidaste tu contraseña?" opens the screen with the '
      'email typed on login', (tester) async {
    await _pumpLogin(tester, _gateway());
    await tester.enterText(find.byKey(const Key('login_email')), _email);

    await _openForgot(tester);

    expect(find.text('Recuperar contraseña'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, _email), findsOneWidget);
  });

  testWidgets('AC1 · an invalid email on login is not prefilled', (
    tester,
  ) async {
    await _pumpLogin(tester, _gateway());
    await tester.enterText(find.byKey(const Key('login_email')), 'ana@');

    await _openForgot(tester);

    expect(tester.widget<TextFormField>(_emailField).controller?.text, '');
  });

  testWidgets('AC2 · sends the code and moves to step 2 with the email', (
    tester,
  ) async {
    final requests = await _pumpLogin(tester, _gateway());
    await _openForgot(tester);

    await _requestCode(tester);

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, endsWith('/auth/password/forgot'));
    expect(_body(request), {'email': _email});
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(find.text(_sent), findsOneWidget);
    expect(
      find.textContaining(_email, findRichText: true),
      findsOneWidget,
    ); // "…que enviamos a ana@mail.com…"
    expect(_code, findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('AC3 · empty or invalid email: no request', (tester) async {
    final requests = await _pumpLogin(tester, _gateway());
    await _openForgot(tester);

    await tester.tap(_send);
    await tester.pump();
    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);

    await _requestCode(tester, email: 'ana@');
    expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('AC3 · unknown email (422): the message under the field', (
    tester,
  ) async {
    const unknown = 'El correo seleccionado no es válido.';
    await _pumpLogin(
      tester,
      _gateway(
        forgot: () async => _json(
          validationErrors({
            'email': [unknown],
          }),
          422,
        ),
      ),
    );
    await _openForgot(tester);

    await _requestCode(tester, email: 'nadie@mail.com');

    expect(find.text(unknown), findsOneWidget);
    expect(_code, findsNothing); // still on step 1
  });

  testWidgets('AC4 · requirements checklist; nothing is sent until the code '
      'and the password are valid', (tester) async {
    final requests = await _pumpLogin(tester, _gateway());
    await _openForgot(tester);
    await _requestCode(tester);
    requests.clear();

    await _fillReset(tester, code: '123', password: 'abc', confirm: 'abd');
    expect(find.text('Mínimo 8 caracteres'), findsOneWidget);
    expect(find.text('Una letra mayúscula'), findsOneWidget);
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(find.text('El código tiene 6 dígitos'), findsOneWidget);
    expect(find.text('La contraseña no es segura'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(requests, isEmpty);
    await _unmount(tester);
  });

  testWidgets('AC5 · success: back to login with the message and the email '
      'prefilled', (tester) async {
    final requests = await _pumpLogin(tester, _gateway());
    await _openForgot(tester);
    await _requestCode(tester);

    await _fillReset(tester);
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    final reset = requests.last;
    expect(reset.url.path, endsWith('/auth/password/reset'));
    expect(_body(reset), {
      'email': _email,
      'code': '123456',
      'password': _strong,
      'password_confirmation': _strong,
    });
    expect(find.text('Recuperar contraseña'), findsNothing);
    expect(find.text(_done), findsOneWidget);
    final loginEmail = tester.widget<TextFormField>(
      find.byKey(const Key('login_email')),
    );
    expect(loginEmail.controller?.text, _email);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('login_password')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  for (final message in [
    'El código ingresado es incorrecto.',
    'El código ha expirado. Solicita uno nuevo.',
  ]) {
    testWidgets('AC6 · 400 "$message": under the code, which is cleared; the '
        'passwords stay', (tester) async {
      await _pumpLogin(
        tester,
        _gateway(
          reset: () async =>
              _json(jsonApiError(400, 'Incorrect Code', message), 400),
        ),
      );
      await _openForgot(tester);
      await _requestCode(tester);
      await _fillReset(tester);

      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(tester.widget<TextFormField>(_code).controller?.text, isEmpty);
      expect(tester.widget<TextFormField>(_password).controller?.text, _strong);
      expect(find.text('Recuperar contraseña'), findsOneWidget);
      await _unmount(tester);
    });
  }

  testWidgets('AC7 · "Reenviar código" waits 60 s, then asks again and '
      'restarts the wait', (tester) async {
    final requests = await _pumpLogin(tester, _gateway());
    await _openForgot(tester);
    await _requestCode(tester);

    bool enabled() => tester.widget<TextButton>(_resend).onPressed != null;
    expect(enabled(), isFalse);
    expect(find.text('Reenviar código en 1:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 60));
    expect(enabled(), isTrue);
    await tester.tap(_resend);
    await tester.pumpAndSettle();

    expect(
      requests.where((r) => r.url.path.endsWith('/password/forgot')),
      hasLength(2),
    );
    expect(_body(requests.last), {'email': _email});
    expect(enabled(), isFalse);
    await _unmount(tester);
  });

  testWidgets('AC8 · weak / compromised password (422): under the password', (
    tester,
  ) async {
    const compromised =
        'La contraseña ha aparecido en una filtración de datos. Elige otra.';
    await _pumpLogin(
      tester,
      _gateway(
        reset: () async => _json(
          validationErrors({
            'password': [compromised],
          }),
          422,
        ),
      ),
    );
    await _openForgot(tester);
    await _requestCode(tester);
    await _fillReset(tester);

    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(find.text(compromised), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('AC8 · 429: "Demasiados intentos…" without "Reintentar"', (
    tester,
  ) async {
    await _pumpLogin(
      tester,
      _gateway(
        forgot: () async =>
            _json(jsonApiError(429, 'Too Many Requests', 'Too many'), 429),
      ),
    );
    await _openForgot(tester);

    await _requestCode(tester);

    expect(
      find.text('Demasiados intentos. Espera un momento e inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('AC8 · no connection: message + "Reintentar", what was typed '
      'is kept', (tester) async {
    var offline = true;
    await _pumpLogin(
      tester,
      _gateway(
        reset: () async {
          if (offline) throw const SocketException('offline');
          return _json(metaMessage(_done), 200);
        },
      ),
    );
    await _openForgot(tester);
    await _requestCode(tester);
    await _fillReset(tester);

    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(find.text('Sin conexión a Internet.'), findsOneWidget);
    expect(tester.widget<TextFormField>(_code).controller?.text, '123456');
    expect(tester.widget<TextFormField>(_password).controller?.text, _strong);

    offline = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text(_done), findsOneWidget);
  });

  testWidgets('AC9 · spinner and disabled button while sending (no double '
      'submit)', (tester) async {
    final gate = Completer<void>();
    final requests = await _pumpLogin(
      tester,
      _gateway(
        forgot: () async {
          await gate.future;
          return _json(metaMessage(_sent), 200);
        },
      ),
    );
    await _openForgot(tester);
    await tester.enterText(_emailField, _email);

    await tester.tap(_send);
    await tester.pump();
    expect(
      find.descendant(
        of: _send,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.descendant(of: _send, matching: find.byType(ElevatedButton)),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(_send);
    await tester.pump();
    expect(requests, hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();
    await _unmount(tester);
  });

  testWidgets('AC9 · "Usar otro correo" and "Volver"', (tester) async {
    await _pumpLogin(tester, _gateway());
    await _openForgot(tester);
    await _requestCode(tester);

    await tester.tap(find.byKey(const Key('forgot_change_email')));
    await tester.pumpAndSettle();
    expect(_emailField, findsOneWidget);
    expect(_code, findsNothing);

    await tester.tap(find.byKey(const Key('forgot_back')));
    await tester.pumpAndSettle();
    expect(find.text('Recuperar contraseña'), findsNothing);
    expect(find.byKey(const Key('login_email')), findsOneWidget);
  });

  testWidgets('AC9 · fits a 320 × 568 phone on both steps', (tester) async {
    await _pumpLogin(tester, _gateway(), size: const Size(640, 1136), ratio: 2);
    await _openForgot(tester);
    expect(tester.takeException(), isNull);

    await _requestCode(tester);
    await _fillReset(tester, password: 'abc');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
