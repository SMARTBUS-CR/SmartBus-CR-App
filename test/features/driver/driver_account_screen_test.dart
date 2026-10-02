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
import 'package:smartbus_drivers/features/driver/driver_account_screen.dart';

import '../auth/auth_fixtures.dart';

// ---------------------------------------------------------------------------
// Test harness: DriverAccountScreen wired to a fake Gateway (MockClient).
// ---------------------------------------------------------------------------

typedef _Handler = Future<http.Response> Function(http.Request request);

final _name = find.byKey(const Key('profile_name'));
final _email = find.byKey(const Key('profile_email'));
final _role = find.byKey(const Key('profile_role'));
final _avatar = find.byKey(const Key('profile_avatar'));
final _refreshing = find.byKey(const Key('profile_refreshing'));
final _readOnlyNotice = find.byKey(const Key('profile_read_only_notice'));
final _error = find.byKey(const Key('profile_error'));
final _retry = find.byKey(const Key('profile_retry'));
final _logout = find.byKey(const Key('profile_logout'));

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _driverDocument({
  String name = 'Carlos Mora',
  String email = 'carlos@empresa.com',
}) => userDocument(
  id: driverId,
  name: name,
  email: email,
  role: 'driver',
  roleLabel: 'Conductor',
);

/// Stores a driver session like the one left by login, then pumps the account
/// screen. Pass `storedUser: false` to start without a stored user. Returns the
/// sent requests.
Future<List<http.Request>> _pumpScreen(
  WidgetTester tester,
  _Handler handler, {
  bool storedUser = true,
  String storedName = 'Carlos Mora',
  Size size = const Size(1080, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final store = SecureSessionStore();
  await store.saveToken('stored-token');
  if (storedUser) {
    await store.saveUser(
      AuthUser.fromJsonApi(_driverDocument(name: storedName)).toJson(),
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
      initialRoute: '/driver/account',
      routes: {
        '/login': (_) => const Scaffold(body: Text('LOGIN')),
        '/driver/home': (_) => const Scaffold(body: Text('DRIVER HOME')),
        '/driver/account': (_) =>
            DriverAccountScreen(authService: service, sessionStore: store),
      },
    ),
  );
  // Let the stored user load (secure storage is async).
  await tester.pump();
  await tester.pump();

  return requests;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('AC1 · profile data', () {
    testWidgets('shows name, email, "Conductor", initials and logout',
        (tester) async {
      await _pumpScreen(tester, (_) async => _json(_driverDocument(), 200));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(_name).data, 'Carlos Mora');
      expect(tester.widget<Text>(_email).data, 'carlos@empresa.com');
      expect(tester.widget<Text>(_role).data, 'Conductor');
      expect(
        find.descendant(of: _avatar, matching: find.text('CM')),
        findsOneWidget,
      );
      expect(find.text('Cerrar sesión'), findsOneWidget);
      // The internal user ID (UUID) is never shown.
      expect(find.textContaining(driverId), findsNothing);
    });

    testWidgets('"Cerrar sesión" signs out and opens login', (tester) async {
      final requests = await _pumpScreen(tester, (request) async {
        if (request.url.path.endsWith('/auth/logout')) {
          return _json(metaMessage('Sesión cerrada.'), 200);
        }
        return _json(_driverDocument(), 200);
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

  group('AC2 · read-only', () {
    testWidgets('no inputs or edit actions, and the admin notice is shown',
        (tester) async {
      await _pumpScreen(tester, (_) async => _json(_driverDocument(), 200));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.textContaining('Editar'), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(_readOnlyNotice, findsOneWidget);
      expect(
        find.text(
          'Para actualizar tus datos, contacta al administrador de tu empresa.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('only GET requests are sent while viewing the profile',
        (tester) async {
      var calls = 0;
      final requests = await _pumpScreen(tester, (_) async {
        calls++;
        if (calls == 1) throw const SocketException('offline');
        return _json(_driverDocument(), 200);
      });
      await tester.pumpAndSettle();
      await tester.tap(_retry);
      await tester.pumpAndSettle();

      expect(requests, hasLength(2));
      expect(requests.map((r) => r.method), everyElement('GET'));
    });
  });

  group('AC3 · fresh data from the backend', () {
    testWidgets('calls GET /auth/user?include=roles with the stored token',
        (tester) async {
      final requests = await _pumpScreen(
        tester,
        (_) async => _json(_driverDocument(), 200),
      );
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, endsWith('/auth/user'));
      expect(request.url.queryParameters['include'], 'roles');
      expect(request.headers['Authorization'], 'Bearer stored-token');
    });

    testWidgets('shows stored data while loading, then the admin-updated name',
        (tester) async {
      final response = Completer<http.Response>();
      await _pumpScreen(tester, (_) => response.future);

      expect(tester.widget<Text>(_name).data, 'Carlos Mora');
      expect(_refreshing, findsOneWidget);

      // The administrator changed the name in the admin panel.
      response.complete(_json(_driverDocument(name: 'Carlos A. Mora'), 200));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(_name).data, 'Carlos A. Mora');
      expect(_refreshing, findsNothing);
      expect(
        (await SecureSessionStore().readUser())?['name'],
        'Carlos A. Mora',
      );
    });

    testWidgets('without a stored user shows a spinner while loading',
        (tester) async {
      final response = Completer<http.Response>();
      await _pumpScreen(tester, (_) => response.future, storedUser: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_name, findsNothing);

      response.complete(_json(_driverDocument(), 200));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(_name).data, 'Carlos Mora');
    });
  });

  group('AC4 · session expired (401)', () {
    testWidgets('clears the session and opens login with the message',
        (tester) async {
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

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    });
  });

  group('AC5 · network errors / timeout', () {
    final failures = <String, _Handler>{
      'no connection': (_) async => throw const SocketException('offline'),
      'timeout': (_) async => throw TimeoutException('slow'),
      '503': (_) async => _json({'message': 'Service Unavailable'}, 503),
      '500': (_) async => _json({'message': 'Server Error'}, 500),
    };

    for (final entry in failures.entries) {
      testWidgets('${entry.key}: keeps the stored data and offers retry',
          (tester) async {
        await _pumpScreen(tester, entry.value);
        await tester.pumpAndSettle();

        expect(tester.widget<Text>(_name).data, 'Carlos Mora');
        expect(_error, findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(await SecureSessionStore().readToken(), 'stored-token');
      });
    }

    testWidgets('"Reintentar" calls the endpoint again', (tester) async {
      var calls = 0;
      final requests = await _pumpScreen(tester, (_) async {
        calls++;
        if (calls == 1) throw const SocketException('offline');
        return _json(_driverDocument(name: 'Carlos A. Mora'), 200);
      });
      await tester.pumpAndSettle();

      await tester.tap(_retry);
      await tester.pumpAndSettle();

      expect(requests, hasLength(2));
      expect(_error, findsNothing);
      expect(tester.widget<Text>(_name).data, 'Carlos A. Mora');
    });
  });

  group('AC6 · long text', () {
    testWidgets('long name and email do not overflow on a small screen',
        (tester) async {
      final longName = 'Carlos Alberto de la Santísima Trinidad ' * 6;
      final longEmail = '${'c' * 120}@empresa-de-transporte-muy-larga.co.cr';

      await _pumpScreen(
        tester,
        (_) async => _json(
          _driverDocument(name: longName.trim(), email: longEmail),
          200,
        ),
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
}
