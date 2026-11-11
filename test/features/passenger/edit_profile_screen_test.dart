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
import 'package:smartbus_drivers/features/auth/verify_email_screen.dart';
import 'package:smartbus_drivers/features/passenger/edit_profile_screen.dart';

import '../auth/auth_fixtures.dart';

// ---------------------------------------------------------------------------
// Test harness: EditProfileScreen pushed over a fake profile, wired to a fake
// Gateway (MockClient).
// ---------------------------------------------------------------------------

typedef _Handler = Future<http.Response> Function(http.Request request);

final _name = find.byKey(const Key('edit_profile_name'));
final _email = find.byKey(const Key('edit_profile_email'));
final _currentPassword = find.byKey(const Key('edit_profile_current_password'));
final _save = find.byKey(const Key('edit_profile_save'));

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

final _user = AuthUser.fromJsonApi(
  userDocument(name: 'Ana Pérez', email: 'ana@mail.com'),
);

class _Harness {
  final requests = <http.Request>[];

  /// What the edit screen popped with (null until it pops).
  Object? popResult;
  bool popped = false;
}

Future<_Harness> _pumpScreen(WidgetTester tester, _Handler handler) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final h = _Harness();
  final store = SecureSessionStore();
  await store.saveToken('stored-token');
  await store.saveUser(_user.toJson());

  final service = AuthService(
    client: ApiClient(
      sessionStore: store,
      httpClient: MockClient((request) async {
        h.requests.add(request);
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
      onGenerateRoute: (settings) {
        if (settings.name != '/verify-email') return null;
        final args = settings.arguments! as VerifyEmailArgs;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(
            body: Text('VERIFY ${args.email} resend=${args.resendOnOpen}'),
          ),
        );
      },
    ),
  );

  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  unawaited(
    navigator
        .push<Object?>(
          MaterialPageRoute(
            builder: (_) => EditProfileScreen(
              user: _user,
              authService: service,
              sessionStore: store,
            ),
          ),
        )
        .then((result) {
          h.popped = true;
          h.popResult = result;
        }),
  );
  await tester.pumpAndSettle();
  return h;
}

String _fieldText(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .controller
    .text;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('AC2 · form', () {
    testWidgets('name and email are pre-filled', (tester) async {
      await _pumpScreen(tester, (_) async => _json({}, 500));

      expect(_fieldText(tester, _name), 'Ana Pérez');
      expect(_fieldText(tester, _email), 'ana@mail.com');
    });

    testWidgets('"Contraseña actual" appears only when the email changes', (
      tester,
    ) async {
      await _pumpScreen(tester, (_) async => _json({}, 500));
      expect(_currentPassword, findsNothing);

      await tester.enterText(_email, 'nuevo@mail.com');
      await tester.pumpAndSettle();
      expect(_currentPassword, findsOneWidget);
      expect(
        find.byKey(const Key('edit_profile_email_notice')),
        findsOneWidget,
      );

      // Same address, different case: not a change.
      await tester.enterText(_email, 'ANA@mail.com');
      await tester.pumpAndSettle();
      expect(_currentPassword, findsNothing);
    });
  });

  group('AC3 · client-side validation', () {
    testWidgets('empty name and email', (tester) async {
      final h = await _pumpScreen(tester, (_) async => _json({}, 500));

      await tester.enterText(_name, '');
      await tester.enterText(_email, '');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('Ingresa tu nombre'), findsOneWidget);
      expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
      expect(h.requests, isEmpty);
    });

    testWidgets('name > 100 chars and invalid email', (tester) async {
      final h = await _pumpScreen(tester, (_) async => _json({}, 500));

      await tester.enterText(_name, 'a' * 101);
      await tester.enterText(_email, 'ana@mail');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(
        find.text('El nombre no puede superar 100 caracteres'),
        findsOneWidget,
      );
      expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
      expect(h.requests, isEmpty);
    });

    testWidgets('email changed without the current password', (tester) async {
      final h = await _pumpScreen(tester, (_) async => _json({}, 500));

      await tester.enterText(_email, 'nuevo@mail.com');
      await tester.pumpAndSettle();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(
        find.text('Ingresa tu contraseña actual para cambiar el correo'),
        findsOneWidget,
      );
      expect(h.requests, isEmpty);
    });
  });

  group('AC4 · only changed fields are sent', () {
    testWidgets('no changes: no request and back to the profile', (
      tester,
    ) async {
      final h = await _pumpScreen(tester, (_) async => _json({}, 500));

      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(h.requests, isEmpty);
      expect(find.text('ACCOUNT'), findsOneWidget);
    });

    testWidgets('only the name: PATCH with { name } only', (tester) async {
      final h = await _pumpScreen(
        tester,
        (_) async =>
            _json(userDocument(name: 'Ana Rojas', email: 'ana@mail.com'), 200),
      );

      await tester.enterText(_name, '  Ana Rojas ');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      final request = h.requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.path, endsWith('/auth/user'));
      expect(request.url.queryParameters['include'], 'roles');
      expect(jsonDecode(request.body), {'name': 'Ana Rojas'});
    });
  });

  group('AC5 · successful update', () {
    testWidgets('name: stores the user, shows the message and returns it', (
      tester,
    ) async {
      final h = await _pumpScreen(
        tester,
        (_) async =>
            _json(userDocument(name: 'Ana Rojas', email: 'ana@mail.com'), 200),
      );

      await tester.enterText(_name, 'Ana Rojas');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('Perfil actualizado correctamente.'), findsOneWidget);
      expect(h.popped, isTrue);
      expect((h.popResult! as AuthUser).name, 'Ana Rojas');
      expect((await SecureSessionStore().readUser())?['name'], 'Ana Rojas');
      expect(await SecureSessionStore().readToken(), 'stored-token');
    });

    testWidgets('email: clears the session and opens the verification with a '
        'new code', (tester) async {
      final h = await _pumpScreen(
        tester,
        (_) async => _json(userDocument(email: 'nuevo@mail.com'), 200),
      );

      await tester.enterText(_email, ' nuevo@mail.com ');
      await tester.pumpAndSettle();
      await tester.enterText(_currentPassword, 'Secret#123');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(jsonDecode(h.requests.single.body), {
        'email': 'nuevo@mail.com',
        'current_password': 'Secret#123',
      });
      expect(find.text('VERIFY nuevo@mail.com resend=true'), findsOneWidget);
      expect(await SecureSessionStore().hasSession(), isFalse);

      // Nothing to go back to: the old session no longer works.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    });
  });

  group('AC6 · backend errors (422)', () {
    testWidgets('messages under each field, typed values kept', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => _json(
          validationErrors({
            'email': ['El correo electrónico ya ha sido registrado.'],
            'current_password': ['La contraseña es incorrecta.'],
          }),
          422,
        ),
      );

      await tester.enterText(_email, 'usado@mail.com');
      await tester.pumpAndSettle();
      await tester.enterText(_currentPassword, 'wrong');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(
        find.text('El correo electrónico ya ha sido registrado.'),
        findsOneWidget,
      );
      expect(find.text('La contraseña es incorrecta.'), findsOneWidget);
      expect(_fieldText(tester, _email), 'usado@mail.com');
      expect(await SecureSessionStore().readToken(), 'stored-token');
    });
  });

  group('AC10 · loading, session and network', () {
    testWidgets('spinner and disabled button while saving', (tester) async {
      final response = Completer<http.Response>();
      final h = await _pumpScreen(tester, (_) => response.future);

      await tester.enterText(_name, 'Ana Rojas');
      await tester.tap(_save);
      await tester.pump();

      expect(
        find.descendant(
          of: _save,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.descendant(of: _save, matching: find.byType(ElevatedButton)),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(_save, warnIfMissed: false);
      await tester.pump();
      expect(h.requests, hasLength(1));

      response.complete(_json(userDocument(name: 'Ana Rojas'), 200));
      await tester.pumpAndSettle();
    });

    testWidgets('401: clears the session and goes to login', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => _json({'message': 'Invalid or expired token.'}, 401),
      );

      await tester.enterText(_name, 'Ana Rojas');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('LOGIN'), findsOneWidget);
      expect(
        find.text('Tu sesión expiró. Inicia sesión nuevamente.'),
        findsOneWidget,
      );
      expect(await SecureSessionStore().hasSession(), isFalse);
    });

    testWidgets('no connection: SnackBar and the typed values are kept', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        (_) async => throw const SocketException('offline'),
      );

      await tester.enterText(_name, 'Ana Rojas');
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión a Internet.'), findsOneWidget);
      expect(_fieldText(tester, _name), 'Ana Rojas');
      expect(
        tester
            .widget<ElevatedButton>(
              find.descendant(of: _save, matching: find.byType(ElevatedButton)),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('429: throttling message', (tester) async {
      await _pumpScreen(
        tester,
        (_) async =>
            _json(jsonApiError(429, 'Too Many Requests', 'Too many'), 429),
      );

      await tester.enterText(_name, 'Ana Rojas');
      await tester.tap(_save);
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
