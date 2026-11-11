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
import 'package:smartbus_drivers/core/theme.dart';
import 'package:smartbus_drivers/features/auth/models/auth_user.dart';
import 'package:smartbus_drivers/features/auth/services/auth_service.dart';
import 'package:smartbus_drivers/features/passenger/passenger_account_screen.dart';

import '../auth/auth_fixtures.dart';

// ---------------------------------------------------------------------------
// Test harness: PassengerAccountScreen wired to a fake Gateway (MockClient).
// ---------------------------------------------------------------------------

typedef _Handler = Future<http.Response> Function(http.Request request);

final _name = find.byKey(const Key('profile_name'));
final _email = find.byKey(const Key('profile_email'));
final _role = find.byKey(const Key('profile_role'));
final _avatar = find.byKey(const Key('profile_avatar'));
final _refreshing = find.byKey(const Key('profile_refreshing'));
final _error = find.byKey(const Key('profile_error'));
final _retry = find.byKey(const Key('profile_retry'));
final _logout = find.byKey(const Key('profile_logout'));

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Stores a session like the one left by login, then pumps the account screen.
/// Pass `storedUser: null` to start without a stored user. Returns the sent
/// requests.
Future<List<http.Request>> _pumpScreen(
  WidgetTester tester,
  _Handler handler, {
  Map<String, dynamic>? storedUser = const {},
  Size size = const Size(1080, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final store = SecureSessionStore();
  await store.saveToken('stored-token');
  if (storedUser != null) {
    await store.saveUser(
      storedUser.isEmpty
          ? AuthUser.fromJsonApi(userDocument(name: 'Ana Pérez')).toJson()
          : storedUser,
    );
  }

  final requests = <http.Request>[];
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
      initialRoute: '/passenger/account',
      routes: {
        '/login': (_) => const Scaffold(body: Text('LOGIN')),
        '/passenger/home': (_) => const Scaffold(body: Text('PASSENGER HOME')),
        '/passenger/trips': (_) => const Scaffold(body: Text('TRIPS')),
        '/passenger/account': (_) =>
            PassengerAccountScreen(authService: service, sessionStore: store),
        '/passenger/account/password': (_) =>
            const Scaffold(body: Text('CHANGE PASSWORD')),
      },
      // Stub of "Editar perfil": shows the user it received and, on tap,
      // stores a renamed user and pops (like a successful save).
      onGenerateRoute: (settings) {
        if (settings.name != '/passenger/account/edit') return null;
        final user = settings.arguments! as AuthUser;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await store.saveUser(
                  user.copyWith(name: 'Ana Editada').toJson(),
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: Text('EDIT ${user.name}'),
            ),
          ),
        );
      },
    ),
  );
  // Let the stored user load (secure storage is async).
  await tester.pump();
  await tester.pump();

  return requests;
}

Map<String, dynamic> _storedUser({
  String name = 'Ana Pérez',
  String email = 'user@passenger.com',
}) => AuthUser.fromJsonApi(userDocument(name: name, email: email)).toJson();

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('AC1 · profile data', () {
    testWidgets('shows name, email, ID, role, initials and logout', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        (_) async =>
            _json(userDocument(name: 'Ana Pérez', email: 'ana@mail.com'), 200),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(_name).data, 'Ana Pérez');
      expect(tester.widget<Text>(_email).data, 'ana@mail.com');
      expect(tester.widget<Text>(_role).data, 'Pasajero');
      // The internal user ID (UUID) is never shown.
      expect(find.textContaining(passengerId), findsNothing);
      expect(find.text('ID de usuario'), findsNothing);
      expect(
        find.descendant(of: _avatar, matching: find.text('AP')),
        findsOneWidget,
      );
      expect(_logout, findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    testWidgets('single-word name uses one initial', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => _json(userDocument(name: 'ana'), 200),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _avatar, matching: find.text('A')),
        findsOneWidget,
      );
    });

    testWidgets('"Cerrar sesión" signs out and opens login', (tester) async {
      final requests = await _pumpScreen(tester, (request) async {
        if (request.url.path.endsWith('/auth/logout')) {
          return _json(metaMessage('Sesión cerrada.'), 200);
        }
        return _json(userDocument(), 200);
      });
      await tester.pumpAndSettle();

      await tester.tap(_logout);
      await tester.pumpAndSettle();

      expect(requests.last.method, 'POST');
      expect(requests.last.url.path, endsWith('/auth/logout'));
      expect(find.text('LOGIN'), findsOneWidget);
      expect(await SecureSessionStore().readToken(), isNull);
    });
  });

  group('AC2 · fresh data from the backend', () {
    testWidgets('calls GET /auth/user?include=roles with the stored token', (
      tester,
    ) async {
      final requests = await _pumpScreen(
        tester,
        (_) async => _json(userDocument(), 200),
      );
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, endsWith('/auth/user'));
      expect(request.url.queryParameters['include'], 'roles');
      expect(request.headers['Authorization'], 'Bearer stored-token');
    });

    testWidgets('shows the stored data while loading, then updates it', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      await _pumpScreen(
        tester,
        (_) => response.future,
        storedUser: _storedUser(name: 'Ana Pérez'),
      );

      // Loading: the stored user is visible (no empty screen).
      expect(tester.widget<Text>(_name).data, 'Ana Pérez');
      expect(_refreshing, findsOneWidget);

      response.complete(
        _json(userDocument(name: 'Ana P. Rojas', email: 'new@mail.com'), 200),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(_name).data, 'Ana P. Rojas');
      expect(tester.widget<Text>(_email).data, 'new@mail.com');
      expect(_refreshing, findsNothing);
      expect((await SecureSessionStore().readUser())?['name'], 'Ana P. Rojas');
    });

    testWidgets('without a stored user shows a spinner while loading', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      await _pumpScreen(tester, (_) => response.future, storedUser: null);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_name, findsNothing);

      response.complete(_json(userDocument(name: 'Ana Pérez'), 200));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(_name).data, 'Ana Pérez');
    });
  });

  group('AC3 · session expired (401)', () {
    testWidgets('clears the session and opens login with the message', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        (_) async => _json({'message': 'Invalid or expired token.'}, 401),
      );
      await tester.pumpAndSettle();

      expect(find.text('LOGIN'), findsOneWidget);
      expect(
        find.text('Tu sesión expiró. Inicia sesión nuevamente.'),
        findsOneWidget,
      );
      expect(await SecureSessionStore().readToken(), isNull);
      expect(await SecureSessionStore().readUser(), isNull);

      // Back does not return to the account screen.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    });
  });

  group('AC4 · network errors / timeout', () {
    final failures = <String, _Handler>{
      'no connection': (_) async => throw const SocketException('offline'),
      'timeout': (_) async => throw TimeoutException('slow'),
      '503': (_) async => _json({'message': 'Service Unavailable'}, 503),
      '500': (_) async => _json({'message': 'Server Error'}, 500),
    };

    for (final entry in failures.entries) {
      testWidgets('${entry.key}: keeps the stored data and offers retry', (
        tester,
      ) async {
        await _pumpScreen(tester, entry.value);
        await tester.pumpAndSettle();

        expect(tester.widget<Text>(_name).data, 'Ana Pérez');
        expect(_error, findsOneWidget);
        expect(_retry, findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(await SecureSessionStore().readToken(), 'stored-token');
      });
    }

    testWidgets('shows the connection message', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => throw const SocketException('offline'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión a Internet.'), findsOneWidget);
    });

    testWidgets('"Reintentar" calls the endpoint again', (tester) async {
      var calls = 0;
      final requests = await _pumpScreen(tester, (_) async {
        calls++;
        if (calls == 1) throw const SocketException('offline');
        return _json(userDocument(name: 'Ana Rojas'), 200);
      });
      await tester.pumpAndSettle();

      await tester.tap(_retry);
      await tester.pumpAndSettle();

      expect(requests, hasLength(2));
      expect(requests.last.url.path, endsWith('/auth/user'));
      expect(_error, findsNothing);
      expect(tester.widget<Text>(_name).data, 'Ana Rojas');
    });

    testWidgets('without stored data the error still offers retry', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        (_) async => throw const SocketException('offline'),
        storedUser: null,
      );
      await tester.pumpAndSettle();

      expect(_retry, findsOneWidget);
      expect(_logout, findsOneWidget);
    });
  });

  group('AC5 · long text', () {
    testWidgets('long name and email do not overflow on a small screen', (
      tester,
    ) async {
      final longName = 'María Fernanda de los Ángeles ' * 6;
      final longEmail = '${'a' * 120}@correo-muy-largo-de-pruebas.co.cr';

      await _pumpScreen(
        tester,
        (_) async =>
            _json(userDocument(name: longName.trim(), email: longEmail), 200),
        // 320 × 568 logical pixels (iPhone SE size) at the harness' 2.75 ratio.
        size: const Size(880, 1562),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final finder in [_name, _email]) {
        final text = tester.widget<Text>(finder);
        expect(text.maxLines, 2);
        expect(text.overflow, TextOverflow.ellipsis);
      }
    });
  });

  group('Edit profile / change password entries', () {
    final edit = find.byKey(const Key('profile_edit'));
    final changePassword = find.byKey(const Key('profile_change_password'));

    testWidgets('AC1: passengers see both entries', (tester) async {
      await _pumpScreen(tester, (_) async => _json(userDocument(), 200));
      await tester.pumpAndSettle();

      expect(edit, findsOneWidget);
      expect(find.text('Editar perfil'), findsOneWidget);
      expect(changePassword, findsOneWidget);
      expect(find.text('Cambiar contraseña'), findsOneWidget);
    });

    testWidgets('"Editar perfil" opens with the current user and the new '
        'data shows right away on return', (tester) async {
      final requests = await _pumpScreen(
        tester,
        (_) async => _json(userDocument(name: 'Ana Pérez'), 200),
      );
      await tester.pumpAndSettle();

      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('EDIT Ana Pérez'), findsOneWidget);

      await tester.tap(find.text('EDIT Ana Pérez'));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(_name).data, 'Ana Editada');
      expect(requests, hasLength(1)); // no extra GET to refresh
    });

    testWidgets('"Cambiar contraseña" opens its screen', (tester) async {
      await _pumpScreen(tester, (_) async => _json(userDocument(), 200));
      await tester.pumpAndSettle();

      await tester.tap(changePassword);
      await tester.pumpAndSettle();

      expect(find.text('CHANGE PASSWORD'), findsOneWidget);
    });
  });

  group('Delete account (soft delete)', () {
    final deleteButton = find.byKey(const Key('profile_delete_account'));
    final dialog = find.byKey(const Key('delete_account_dialog'));
    final cancel = find.byKey(const Key('delete_account_cancel'));
    final confirm = find.byKey(const Key('delete_account_confirm'));
    final password = find.byKey(const Key('delete_account_password'));
    final dialogError = find.byKey(const Key('delete_account_error'));
    const deletedMessage = 'Cuenta eliminada correctamente.';

    /// GET /auth/user answers the profile; DELETE /auth/user answers [delete].
    _Handler withDelete(_Handler delete) => (request) async =>
        request.method == 'DELETE' ? delete(request) : _json(userDocument(), 200);

    /// Opens the dialog, types [pass] and taps "Eliminar".
    Future<void> confirmWith(WidgetTester tester, String pass) async {
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.enterText(password, pass);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }

    testWidgets('AC1: red "Eliminar cuenta" button next to "Cerrar sesión"', (
      tester,
    ) async {
      await _pumpScreen(tester, (_) async => _json(userDocument(), 200));
      await tester.pumpAndSettle();

      expect(deleteButton, findsOneWidget);
      expect(find.text('Eliminar cuenta'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(deleteButton)
            .style
            ?.foregroundColor
            ?.resolve({}),
        SmartBusColors.error,
      );
      expect(_logout, findsOneWidget);
    });

    testWidgets('AC3: tapping it opens the confirmation dialog', (
      tester,
    ) async {
      await _pumpScreen(tester, (_) async => _json(userDocument(), 200));
      await tester.pumpAndSettle();

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
      expect(
        find.text('¿Estás seguro? Esta acción no se puede deshacer.'),
        findsOneWidget,
      );
      expect(password, findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);
      expect(
        tester.widget<TextButton>(confirm).style?.foregroundColor?.resolve({}),
        SmartBusColors.error,
      );
    });

    testWidgets('AC4: "Cancelar" closes the dialog and does nothing', (
      tester,
    ) async {
      final requests = await _pumpScreen(
        tester,
        (_) async => _json(userDocument(), 200),
      );
      await tester.pumpAndSettle();

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(requests, hasLength(1)); // only the initial GET /auth/user
      expect(await SecureSessionStore().readToken(), 'stored-token');
    });

    testWidgets('AC4: tapping outside closes the dialog and does nothing', (
      tester,
    ) async {
      await _pumpScreen(tester, (_) async => _json(userDocument(), 200));
      await tester.pumpAndSettle();

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // barrier
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(await SecureSessionStore().readToken(), 'stored-token');
    });

    testWidgets('empty password: asks for it and sends nothing', (
      tester,
    ) async {
      final requests = await _pumpScreen(
        tester,
        withDelete((_) async => _json(metaMessage(deletedMessage), 200)),
      );
      await tester.pumpAndSettle();

      await confirmWith(tester, '');

      expect(dialog, findsOneWidget);
      expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
      expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
    });

    testWidgets('success: calls DELETE /auth/user, clears the session and '
        'opens login without a way back', (tester) async {
      final requests = await _pumpScreen(
        tester,
        withDelete((_) async => _json(metaMessage(deletedMessage), 200)),
      );
      await tester.pumpAndSettle();

      await confirmWith(tester, 'Secret1!');

      final delete = requests.singleWhere((r) => r.method == 'DELETE');
      expect(delete.url.path, endsWith('/auth/user'));
      expect(delete.headers['Authorization'], 'Bearer stored-token');
      expect(jsonDecode(delete.body), {
        'current_password': 'Secret1!',
        'confirm_deletion': true,
      });

      expect(find.text('LOGIN'), findsOneWidget);
      expect(find.text(deletedMessage), findsOneWidget);
      expect(await SecureSessionStore().readToken(), isNull);
      expect(await SecureSessionStore().readUser(), isNull);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    });

    testWidgets('while deleting: shows progress and cannot be dismissed', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      await _pumpScreen(tester, withDelete((_) => response.future));
      await tester.pumpAndSettle();

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.enterText(password, 'Secret1!');
      await tester.tap(confirm);
      await tester.pump();

      expect(find.byKey(const Key('delete_account_progress')), findsOneWidget);
      expect(tester.widget<TextButton>(cancel).onPressed, isNull);
      await tester.tapAt(const Offset(10, 10)); // barrier
      await tester.pump();
      expect(dialog, findsOneWidget);

      response.complete(_json(metaMessage(deletedMessage), 200));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('wrong password (422): error under the field, session kept', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        withDelete(
          (_) async => _json(
            validationErrors({
              'current_password': ['La contraseña es incorrecta.'],
            }),
            422,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await confirmWith(tester, 'wrong');

      expect(dialog, findsOneWidget);
      expect(find.text('La contraseña es incorrecta.'), findsOneWidget);
      expect(await SecureSessionStore().readToken(), 'stored-token');
    });

    testWidgets('401: "session expired" and login', (tester) async {
      await _pumpScreen(
        tester,
        withDelete(
          (_) async => _json({'message': 'Invalid or expired token.'}, 401),
        ),
      );
      await tester.pumpAndSettle();

      await confirmWith(tester, 'Secret1!');

      expect(find.text('LOGIN'), findsOneWidget);
      expect(
        find.text('Tu sesión expiró. Inicia sesión nuevamente.'),
        findsOneWidget,
      );
      expect(await SecureSessionStore().readToken(), isNull);
    });

    testWidgets('403: "action not allowed", stays on the profile', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        withDelete(
          (_) async =>
              _json(jsonApiError(403, 'Forbidden', 'Forbidden.'), 403),
        ),
      );
      await tester.pumpAndSettle();

      await confirmWith(tester, 'Secret1!');

      expect(dialog, findsNothing);
      expect(
        find.text('Acción no permitida: esta cuenta no se puede eliminar.'),
        findsOneWidget,
      );
      expect(_name, findsOneWidget);
      expect(await SecureSessionStore().readToken(), 'stored-token');
    });

    testWidgets('no connection: error in the dialog, can retry', (
      tester,
    ) async {
      var deletes = 0;
      await _pumpScreen(
        tester,
        withDelete((_) async {
          deletes++;
          if (deletes == 1) throw const SocketException('offline');
          return _json(metaMessage(deletedMessage), 200);
        }),
      );
      await tester.pumpAndSettle();

      await confirmWith(tester, 'Secret1!');
      expect(dialog, findsOneWidget);
      expect(dialogError, findsOneWidget);
      expect(find.text('Sin conexión a Internet.'), findsWidgets);

      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('AC6: button and dialog fit a small screen', (tester) async {
      await _pumpScreen(
        tester,
        (_) async => _json(userDocument(name: 'María Fernanda ' * 6), 200),
        // 320 × 568 logical pixels at the harness' 2.75 ratio.
        size: const Size(880, 1562),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(dialog, findsOneWidget);
    });
  });
}
