import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/widgets/login_form.dart';
import 'package:smartbus_drivers/widgets/slow_request_hint.dart';

final _email = find.byKey(const Key('login_email'));
final _password = find.byKey(const Key('login_password'));
final _submit = find.text('Iniciar sesión');

// Read from the widget so the test survives copy changes.
final _slowHint = find.text(const SlowRequestHint().message);

/// Pumps the form; [onLogin] defaults to recording the submitted credentials.
Future<List<(String, String)>> _pumpForm(
  WidgetTester tester, {
  Future<void> Function(String email, String password)? onLogin,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final calls = <(String, String)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LoginForm(
            onLogin: (email, password) async {
              calls.add((email, password));
              await onLogin?.call(email, password);
            },
          ),
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  group('real-time validation', () {
    testWidgets('empty form shows both errors and does not log in', (
      tester,
    ) async {
      final calls = await _pumpForm(tester);

      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
      expect(find.text('Ingresa tu contraseña'), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('invalid email shows the error while typing', (tester) async {
      final calls = await _pumpForm(tester);

      await tester.enterText(_email, 'user@');
      await tester.pump();
      expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);

      await tester.enterText(_email, 'user@passenger.com');
      await tester.pump();
      expect(find.text('Ingresa un correo electrónico válido'), findsNothing);
      expect(calls, isEmpty);
    });

    testWidgets(
      'does not enforce sign-up strength rules on existing passwords',
      (tester) async {
        final calls = await _pumpForm(tester);

        await tester.enterText(_email, '  user@driver.com ');
        await tester.enterText(_password, 'driver123');
        await tester.tap(_submit);
        await tester.pumpAndSettle();

        expect(calls, [('user@driver.com', 'driver123')]);
      },
    );
  });

  group('slow server hint', () {
    testWidgets('appears only after 8 s and disappears when done', (
      tester,
    ) async {
      final response = Completer<void>();
      await _pumpForm(tester, onLogin: (_, _) => response.future);

      await tester.enterText(_email, 'user@driver.com');
      await tester.enterText(_password, 'driver123');
      await tester.tap(_submit);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_slowHint, findsNothing);

      await tester.pump(const Duration(seconds: 8));
      expect(_slowHint, findsOneWidget);

      response.complete();
      await tester.pumpAndSettle();
      expect(_slowHint, findsNothing);
    });
  });
}
