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
import 'package:smartbus_drivers/features/auth/services/auth_service.dart';
import 'package:smartbus_drivers/features/auth/verify_email_screen.dart';

import 'auth_fixtures.dart';

// ---------------------------------------------------------------------------
// Test harness: VerifyEmailScreen wired to a fake Gateway (MockClient).
// ---------------------------------------------------------------------------

typedef _Handler = Future<http.Response> Function(http.Request request);

final _code = find.byKey(const Key('verify_code'));
final _verify = find.byKey(const Key('verify_submit'));
final _resend = find.byKey(const Key('verify_resend'));

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _sentMessage = 'Te enviamos un código de verificación a tu correo.';

bool _resendEnabled(WidgetTester tester) =>
    tester.widget<TextButton>(_resend).onPressed != null;

/// Pumps the screen on top of a fake login. Returns the sent requests.
Future<List<http.Request>> _pumpScreen(
  WidgetTester tester,
  _Handler handler, {
  VerifyEmailArgs args = const VerifyEmailArgs(
    email: 'ana@mail.com',
    message: _sentMessage,
  ),
}) async {
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
        '/verify': (_) => VerifyEmailScreen(args: args, authService: service),
        '/passenger/home': (_) => const Scaffold(body: Text('PASSENGER HOME')),
      },
    ),
  );
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/verify');
  await tester.pumpAndSettle();

  return requests;
}

/// Disposes the screen so its cooldown timer does not outlive the test.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('screen', () {
    testWidgets('shows the email, the sign-up message and a resend cooldown', (
      tester,
    ) async {
      final requests = await _pumpScreen(tester, (_) async => _json({}, 500));

      expect(
        find.textContaining('ana@mail.com', findRichText: true),
        findsOneWidget,
      );
      expect(find.text(_sentMessage), findsOneWidget);
      // Code just sent by the sign-up: resend waits 60 s.
      expect(_resendEnabled(tester), isFalse);
      expect(find.text('Reenviar código en 1:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 60));
      expect(_resendEnabled(tester), isTrue);
      expect(find.text('Reenviar código'), findsOneWidget);
      expect(requests, isEmpty);

      await _unmount(tester);
    });
  });

  group('real-time validation', () {
    testWidgets('only digits, max 6, and no request until it is valid', (
      tester,
    ) async {
      final requests = await _pumpScreen(tester, (_) async => _json({}, 500));

      await tester.enterText(_code, '12a');
      await tester.pump();
      expect(find.text('El código tiene 6 dígitos'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12',
      );

      await tester.tap(_verify);
      await tester.pumpAndSettle();
      expect(requests, isEmpty);

      await tester.enterText(_code, '12345678');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '123456',
      );
      expect(find.text('El código tiene 6 dígitos'), findsNothing);

      await _unmount(tester);
    });
  });

  group('verify', () {
    testWidgets('a correct code signs in and opens the passenger home', (
      tester,
    ) async {
      final requests = await _pumpScreen(
        tester,
        (_) async => _json(userDocument(token: 'verified-token'), 200),
      );

      await tester.enterText(_code, '482913');
      await tester.tap(_verify);
      await tester.pumpAndSettle();

      final request = requests.single;
      expect(request.url.path, endsWith('/auth/email/verify'));
      expect(jsonDecode(request.body), {
        'email': 'ana@mail.com',
        'code': '482913',
      });
      expect(find.text('PASSENGER HOME'), findsOneWidget);
      expect(find.textContaining('Correo verificado'), findsOneWidget);
      expect(await SecureSessionStore().readToken(), 'verified-token');

      // Signed in: neither verification nor login stay in the stack.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    });

    testWidgets('shows a spinner and blocks a second submit while sending', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      final requests = await _pumpScreen(tester, (_) => response.future);

      await tester.enterText(_code, '482913');
      await tester.tap(_verify);
      await tester.pump();

      expect(tester.widget<ElevatedButton>(_verify).onPressed, isNull);
      await tester.tap(_verify, warnIfMissed: false);
      await tester.pump();
      expect(requests, hasLength(1));

      response.complete(
        _json(
          jsonApiError(400, 'Bad', 'El código ingresado es incorrecto.'),
          400,
        ),
      );
      await tester.pumpAndSettle();
      await _unmount(tester);
    });

    testWidgets('a wrong code (400) is shown under the field and cleared '
        'when editing', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => _json(
          jsonApiError(400, 'Bad', 'El código ingresado es incorrecto.'),
          400,
        ),
      );

      await tester.enterText(_code, '000000');
      await tester.tap(_verify);
      await tester.pumpAndSettle();

      expect(find.text('El código ingresado es incorrecto.'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(_verify).onPressed, isNotNull);
      expect(await SecureSessionStore().readToken(), isNull);

      await tester.enterText(_code, '00000');
      await tester.pump();
      expect(find.text('El código ingresado es incorrecto.'), findsNothing);

      await _unmount(tester);
    });
  });

  group('resend', () {
    testWidgets('after the cooldown it sends a new code and restarts it', (
      tester,
    ) async {
      final requests = await _pumpScreen(
        tester,
        (_) async => _json(metaMessage(_sentMessage), 200),
      );
      await tester.pump(const Duration(seconds: 60));
      await tester.enterText(_code, '123');

      await tester.tap(_resend);
      await tester.pumpAndSettle();

      final request = requests.single;
      expect(request.url.path, endsWith('/auth/email/resend'));
      expect(jsonDecode(request.body), {'email': 'ana@mail.com'});
      expect(_resendEnabled(tester), isFalse);
      // The typed (old) code is cleared.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      await _unmount(tester);
    });

    testWidgets('from login (resendOnOpen) a code is requested right away', (
      tester,
    ) async {
      final requests = await _pumpScreen(
        tester,
        (_) async => _json(metaMessage(_sentMessage), 200),
        args: const VerifyEmailArgs(email: 'ana@mail.com', resendOnOpen: true),
      );

      expect(requests.single.url.path, endsWith('/auth/email/resend'));
      expect(find.text(_sentMessage), findsOneWidget);
      expect(_resendEnabled(tester), isFalse);

      await _unmount(tester);
    });

    testWidgets('if that first request fails it can be retried at once', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        (_) async => throw const SocketException('offline'),
        args: const VerifyEmailArgs(email: 'ana@mail.com', resendOnOpen: true),
      );

      expect(find.text('Sin conexión a Internet.'), findsOneWidget);
      expect(_resendEnabled(tester), isTrue);

      await _unmount(tester);
    });
  });
}
