import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbus_drivers/core/network/api_client.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/auth/models/auth_user.dart';
import 'package:smartbus_drivers/features/auth/services/auth_service.dart';

import 'auth_fixtures.dart';

// ---------------------------------------------------------------------------
// Test harness: fake Gateway (MockClient) + in-memory secure storage.
// ---------------------------------------------------------------------------

typedef _Handler = Future<http.Response> Function(http.Request request);

class _Harness {
  _Harness(_Handler handler) {
    client = MockClient((request) async {
      requests.add(request);
      return handler(request);
    });
    store = SecureSessionStore();
    service = AuthService(
      client: ApiClient(sessionStore: store, httpClient: client),
      sessionStore: store,
    );
  }

  final List<http.Request> requests = [];
  late final MockClient client;
  late final SecureSessionStore store;
  late final AuthService service;

  /// Requests sent to a Gateway path, e.g. `/auth/logout`.
  Iterable<http.Request> sentTo(String path) =>
      requests.where((r) => r.url.path.endsWith(path));
}

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Stores a previous session, as if the user had logged in before.
Future<void> _storeSession(
  SecureSessionStore store, {
  String role = 'passenger',
}) async {
  await store.saveToken('stored-token');
  await store.saveUser(AuthUser.fromJsonApi(userDocument(role: role)).toJson());
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('login', () {
    test('stores the session and returns a passenger with roles', () async {
      final h = _Harness(
        (_) async => _json(userDocument(token: 'passenger-token'), 200),
      );

      final session = await h.service.login(
        email: 'user@passenger.com',
        password: 'x',
      );

      final request = h.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/auth/login'));
      expect(request.url.queryParameters['include'], 'roles');
      expect(session.accessToken, 'passenger-token');
      expect(session.user.isPassenger, isTrue);
      expect(await h.store.readToken(), 'passenger-token');
    });

    test('maps wrong credentials (422) to badCredentials', () async {
      final h = _Harness(
        (_) async => _json(
          validationErrors({
            'email': ['Las credenciales no coinciden.'],
          }),
          422,
        ),
      );

      await expectLater(
        h.service.login(email: 'user@passenger.com', password: 'wrong'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.badCredentials,
          ),
        ),
      );
      expect(await h.store.hasSession(), isFalse);
    });

    test('maps 403 email_not_verified to emailNotVerified', () async {
      final h = _Harness((_) async => _json(emailNotVerifiedError(), 403));

      await expectLater(
        h.service.login(email: 'user@passenger.com', password: 'Secret123!'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.emailNotVerified)
              .having((e) => e.code, 'code', 'email_not_verified')
              .having(
                (e) => e.message,
                'message',
                'Debes verificar tu correo antes de iniciar sesión.',
              ),
        ),
      );
      expect(await h.store.hasSession(), isFalse);
    });

    test('a 403 without that code stays a plain forbidden', () async {
      final h = _Harness(
        (_) async => _json(jsonApiError(403, 'Forbidden', 'Nope'), 403),
      );

      await expectLater(
        h.service.login(email: 'user@passenger.com', password: 'x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.forbidden,
          ),
        ),
      );
    });
  });

  group('AC1 · registerPassenger', () {
    test(
      'sends the sign-up and returns a pending verification, no session',
      () async {
        final h = _Harness(
          (_) async => _json(pendingVerificationDocument(), 201),
        );

        final pending = await h.service.registerPassenger(
          name: 'Passenger User',
          email: 'user@passenger.com',
          password: 'Secret123!',
          passwordConfirmation: 'Secret123!',
        );

        final request = h.requests.single;
        expect(request.method, 'POST');
        expect(request.url.path, endsWith('/auth/register/passenger'));
        expect(request.url.queryParameters['include'], 'roles');
        expect(jsonDecode(request.body), {
          'name': 'Passenger User',
          'email': 'user@passenger.com',
          'password': 'Secret123!',
          'password_confirmation': 'Secret123!',
        });

        expect(pending.email, 'user@passenger.com');
        expect(
          pending.message,
          'Te enviamos un código de verificación a tu correo.',
        );
        // Not signed in until the email is verified.
        expect(await h.store.hasSession(), isFalse);
        expect(await h.store.readUser(), isNull);
      },
    );
  });

  group('email verification', () {
    test('verifyEmail sends email + code and stores the session', () async {
      final h = _Harness(
        (_) async => _json(userDocument(token: 'verified-token'), 200),
      );

      final session = await h.service.verifyEmail(
        email: 'user@passenger.com',
        code: '482913',
      );

      final request = h.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/auth/email/verify'));
      expect(request.url.queryParameters['include'], 'roles');
      expect(jsonDecode(request.body), {
        'email': 'user@passenger.com',
        'code': '482913',
      });
      expect(session.user.isPassenger, isTrue);
      expect(await h.store.readToken(), 'verified-token');
    });

    test('verifyEmail: wrong or expired code (400) keeps the backend '
        'message and stores nothing', () async {
      final h = _Harness(
        (_) async => _json(
          jsonApiError(
            400,
            'Solicitud incorrecta',
            'El código ingresado es incorrecto.',
          ),
          400,
        ),
      );

      await expectLater(
        h.service.verifyEmail(email: 'user@passenger.com', code: '000000'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.badRequest)
              .having(
                (e) => e.message,
                'message',
                'El código ingresado es incorrecto.',
              ),
        ),
      );
      expect(await h.store.hasSession(), isFalse);
    });

    test(
      'resendVerificationCode posts the email and returns the message',
      () async {
        final h = _Harness(
          (_) async => _json(
            metaMessage('Te enviamos un código de verificación a tu correo.'),
            200,
          ),
        );

        final message = await h.service.resendVerificationCode(
          'user@passenger.com',
        );

        final request = h.requests.single;
        expect(request.url.path, endsWith('/auth/email/resend'));
        expect(jsonDecode(request.body), {'email': 'user@passenger.com'});
        expect(message, 'Te enviamos un código de verificación a tu correo.');
      },
    );

    test('resendVerificationCode: 429 throws tooManyRequests', () async {
      final h = _Harness(
        (_) async => _json(jsonApiError(429, 'Too Many', 'Too many'), 429),
      );

      await expectLater(
        h.service.resendVerificationCode('user@passenger.com'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.tooManyRequests,
          ),
        ),
      );
    });
  });

  group('AC2 · field validation errors', () {
    test(
      'throws validation with fieldErrors per field and stores nothing',
      () async {
        final h = _Harness(
          (_) async => _json(
            validationErrors({
              'email': ['El correo ya está registrado.'],
              'password': [
                'La contraseña debe tener al menos 8 caracteres.',
                'La confirmación de la contraseña no coincide.',
              ],
            }),
            422,
          ),
        );

        final error = await h.service
            .registerPassenger(
              name: 'Passenger User',
              email: 'user@passenger.com',
              password: 'short',
              passwordConfirmation: 'other',
            )
            .then<ApiException?>(
              (_) => null,
              onError: (Object e) => e as ApiException,
            );

        expect(error, isNotNull);
        expect(error!.type, ApiErrorType.validation);
        expect(error.message, 'El correo ya está registrado.');
        expect(error.fieldErrors, {
          'email': ['El correo ya está registrado.'],
          'password': [
            'La contraseña debe tener al menos 8 caracteres.',
            'La confirmación de la contraseña no coincide.',
          ],
        });
        expect(await h.store.hasSession(), isFalse);
        expect(await h.store.readUser(), isNull);
      },
    );
  });

  group('AC3 · sendResetCode', () {
    test('returns the backend message on 200', () async {
      final h = _Harness(
        (_) async =>
            _json(metaMessage('Te enviamos un código de 6 dígitos.'), 200),
      );

      final message = await h.service.sendResetCode('user@passenger.com');

      final request = h.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/auth/password/forgot'));
      expect(jsonDecode(request.body), {'email': 'user@passenger.com'});
      expect(message, 'Te enviamos un código de 6 dígitos.');
    });

    test('throws validation with fieldErrors["email"] on 422', () async {
      final h = _Harness(
        (_) async => _json(
          validationErrors({
            'email': ['El correo seleccionado no es válido.'],
          }),
          422,
        ),
      );

      await expectLater(
        h.service.sendResetCode('nobody@smartbus.test'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.validation)
              .having((e) => e.fieldErrors['email'], 'fieldErrors.email', [
                'El correo seleccionado no es válido.',
              ]),
        ),
      );
    });

    test('throws tooManyRequests on 429', () async {
      final h = _Harness(
        (_) async => _json(
          jsonApiError(429, 'Too Many Requests', 'Too Many Attempts.'),
          429,
        ),
      );

      await expectLater(
        h.service.sendResetCode('user@passenger.com'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.tooManyRequests,
          ),
        ),
      );
    });
  });

  group('AC4 · resetPassword', () {
    test('sends the reset and returns the backend message on 200', () async {
      final h = _Harness(
        (_) async => _json(metaMessage('Tu contraseña fue restablecida.'), 200),
      );

      final message = await h.service.resetPassword(
        email: 'user@passenger.com',
        code: '123456',
        password: 'NewSecret123!',
        passwordConfirmation: 'NewSecret123!',
      );

      final request = h.requests.single;
      expect(request.url.path, endsWith('/auth/password/reset'));
      expect(jsonDecode(request.body), {
        'email': 'user@passenger.com',
        'code': '123456',
        'password': 'NewSecret123!',
        'password_confirmation': 'NewSecret123!',
      });
      expect(message, 'Tu contraseña fue restablecida.');
    });

    test('keeps the backend message on 400 (wrong or expired code)', () async {
      final h = _Harness(
        (_) async => _json(
          jsonApiError(400, 'Code Expired', 'El código ha expirado.'),
          400,
        ),
      );

      await expectLater(
        h.service.resetPassword(
          email: 'user@passenger.com',
          code: '000000',
          password: 'NewSecret123!',
          passwordConfirmation: 'NewSecret123!',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.badRequest)
              .having((e) => e.message, 'message', 'El código ha expirado.'),
        ),
      );
    });
  });

  group('AC5 · restore session', () {
    test(
      'fetchCurrentUser parses JSON:API and stores a complete user',
      () async {
        final h = _Harness(
          (_) async => _json(userDocument(id: driverId, role: 'driver'), 200),
        );
        await _storeSession(h.store);

        final user = await h.service.fetchCurrentUser();

        final request = h.requests.single;
        expect(request.method, 'GET');
        expect(request.url.path, endsWith('/auth/user'));
        expect(request.url.queryParameters['include'], 'roles');
        expect(request.headers['Authorization'], 'Bearer stored-token');

        final stored = AuthUser.fromStorage((await h.store.readUser())!);
        for (final u in [user, stored]) {
          expect(u.id, driverId);
          expect(u.name, isNotEmpty);
          expect(u.email, isNotEmpty);
          expect(u.roles.map((r) => r.value), ['driver']);
        }
      },
    );

    test('restoreSession returns the user when the token is valid', () async {
      final h = _Harness((_) async => _json(userDocument(), 200));
      await _storeSession(h.store);

      final user = await h.service.restoreSession();

      expect(user?.id, passengerId);
      expect(user?.isPassenger, isTrue);
    });

    test('restoreSession clears the session on 401', () async {
      final h = _Harness(
        (_) async => _json(
          jsonApiError(401, 'Unauthorized', 'Authentication is required.'),
          401,
        ),
      );
      await _storeSession(h.store);

      expect(await h.service.restoreSession(), isNull);
      expect(await h.store.hasSession(), isFalse);
    });

    test(
      'restoreSession keeps the stored user when there is no network',
      () async {
        final h = _Harness((_) async => throw const SocketException('offline'));
        await _storeSession(h.store);

        final user = await h.service.restoreSession();

        expect(user?.id, passengerId);
        expect(await h.store.hasSession(), isTrue);
      },
    );

    test('restoreSession returns null without a stored token', () async {
      final h = _Harness((_) async => _json(userDocument(), 200));

      expect(await h.service.restoreSession(), isNull);
      expect(h.requests, isEmpty);
    });
  });

  group('AC6 · only passengers and drivers are allowed', () {
    for (final role in ['super-admin', 'company-admin']) {
      test(
        'login as $role signs out on the server and throws roleNotAllowed',
        () async {
          final h = _Harness((request) async {
            if (request.url.path.endsWith('/auth/logout')) {
              return _json(metaMessage('Sesión cerrada.'), 200);
            }
            return _json(
              userDocument(id: adminId, role: role, token: 'admin-token'),
              200,
            );
          });

          await expectLater(
            h.service.login(email: 'admin@superadmin.com', password: 'x'),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.type, 'type', ApiErrorType.roleNotAllowed)
                  .having(
                    (e) => e.message,
                    'message',
                    'Esta aplicación es solo para pasajeros y conductores.',
                  ),
            ),
          );

          final logout = h.sentTo('/auth/logout').single;
          expect(logout.headers['Authorization'], 'Bearer admin-token');
          expect(await h.store.hasSession(), isFalse);
          expect(await h.store.readUser(), isNull);
        },
      );
    }

    test('verifyEmail rejects a user without an allowed role', () async {
      final h = _Harness((request) async {
        if (request.url.path.endsWith('/auth/logout')) {
          return _json(metaMessage('Sesión cerrada.'), 200);
        }
        return _json(
          userDocument(role: 'company-admin', token: 'unexpected-token'),
          200,
        );
      });

      await expectLater(
        h.service.verifyEmail(email: 'x@smartbus.test', code: '123456'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.roleNotAllowed,
          ),
        ),
      );
      expect(h.sentTo('/auth/logout'), hasLength(1));
      expect(await h.store.hasSession(), isFalse);
    });

    test(
      'restoreSession clears a stored admin session and returns null',
      () async {
        final h = _Harness((request) async {
          if (request.url.path.endsWith('/auth/logout')) {
            return _json(metaMessage('Sesión cerrada.'), 200);
          }
          return _json(userDocument(id: adminId, role: 'super-admin'), 200);
        });
        await _storeSession(h.store, role: 'super-admin');

        expect(await h.service.restoreSession(), isNull);
        expect(h.sentTo('/auth/logout'), hasLength(1));
        expect(await h.store.hasSession(), isFalse);
      },
    );
  });

  group('logout', () {
    test('clears the local session even if the server call fails', () async {
      final h = _Harness(
        (_) async => _json(
          jsonApiError(500, 'Server Error', 'An unexpected error occurred.'),
          500,
        ),
      );
      await _storeSession(h.store);

      await h.service.logout();

      expect(h.sentTo('/auth/logout'), hasLength(1));
      expect(await h.store.hasSession(), isFalse);
    });
  });
}
