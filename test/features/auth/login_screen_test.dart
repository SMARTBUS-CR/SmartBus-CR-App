import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbus_drivers/core/network/api_client.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/auth/login_screen.dart';
import 'package:smartbus_drivers/features/auth/services/auth_service.dart';
import 'package:smartbus_drivers/features/auth/verify_email_screen.dart';

import 'auth_fixtures.dart';

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Pumps the login with a Gateway that answers 403 email_not_verified.
/// Returns the arguments the `/verify-email` route was opened with (if any).
Future<List<VerifyEmailArgs>> _pumpUnverifiedLogin(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final store = SecureSessionStore();
  final service = AuthService(
    client: ApiClient(
      sessionStore: store,
      httpClient: MockClient((_) async => _json(emailNotVerifiedError(), 403)),
    ),
    sessionStore: store,
  );

  final opened = <VerifyEmailArgs>[];
  await tester.pumpWidget(
    MaterialApp(
      home: LoginScreen(authService: service),
      onGenerateRoute: (settings) {
        if (settings.name != '/verify-email') return null;
        opened.add(settings.arguments! as VerifyEmailArgs);
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('VERIFY')),
        );
      },
    ),
  );

  await tester.enterText(find.byKey(const Key('login_email')), 'ana@mail.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'Secret#123');
  await tester.tap(find.text('Iniciar sesión'));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('unverified email (403 email_not_verified)', () {
    testWidgets('offers to verify and opens verification with a new code', (
      tester,
    ) async {
      final opened = await _pumpUnverifiedLogin(tester);

      expect(find.text('Verifica tu correo'), findsOneWidget);
      expect(find.textContaining('Debes verificar tu correo'), findsOneWidget);

      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();

      expect(find.text('VERIFY'), findsOneWidget);
      expect(opened.single.email, 'ana@mail.com');
      expect(opened.single.resendOnOpen, isTrue);
      expect(await SecureSessionStore().readToken(), isNull);
    });

    testWidgets('"Ahora no" stays on the login', (tester) async {
      final opened = await _pumpUnverifiedLogin(tester);

      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(find.text('Iniciar sesión'), findsOneWidget);
    });
  });
}
