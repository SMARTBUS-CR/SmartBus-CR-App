import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbus_drivers/core/network/api_client.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';

/// Error translation of [ApiClient] for the two formats it receives:
/// JSON:API (Auth / GPS services) and Laravel's default (API Gateway).
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<ApiException> errorFor(Object body, int status) async {
    final client = ApiClient(
      sessionStore: SecureSessionStore(),
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode(body), status),
      ),
    );
    try {
      await client.get(Uri.parse('https://gateway.test/api/anything'));
    } on ApiException catch (e) {
      return e;
    }
    fail('Expected an ApiException for HTTP $status');
  }

  test(
    'reads the detail and the field of JSON:API validation errors',
    () async {
      final e = await errorFor({
        'errors': [
          {
            'status': 422,
            'detail': 'El nombre es obligatorio.',
            'source': {'pointer': '/data/attributes/name'},
          },
          {
            'status': 422,
            'detail': 'El correo no es válido.',
            'source': {'pointer': '/data/attributes/email'},
          },
        ],
      }, 422);

      expect(e.type, ApiErrorType.validation);
      expect(e.message, 'El nombre es obligatorio.');
      expect(e.fieldErrors, {
        'name': ['El nombre es obligatorio.'],
        'email': ['El correo no es válido.'],
      });
    },
  );

  test('reads Laravel validation errors (Gateway format)', () async {
    final e = await errorFor({
      'message': 'The email field is required.',
      'errors': {
        'email': ['The email field is required.'],
      },
    }, 422);

    expect(e.message, 'The email field is required.');
    expect(e.fieldErrors, {
      'email': ['The email field is required.'],
    });
  });

  test('keeps the backend message on 400', () async {
    final e = await errorFor({
      'errors': [
        {
          'status': '400',
          'title': 'Incorrect Code',
          'detail': 'El código es incorrecto.',
        },
      ],
    }, 400);

    expect(e.type, ApiErrorType.badRequest);
    expect(e.message, 'El código es incorrecto.');
    expect(e.fieldErrors, isEmpty);
  });

  test('maps 429 from the Gateway throttle to tooManyRequests', () async {
    final e = await errorFor({'message': 'Too Many Attempts.'}, 429);

    expect(e.type, ApiErrorType.tooManyRequests);
  });

  test(
    'keeps the friendly message for 401 instead of the backend one',
    () async {
      final e = await errorFor({
        'errors': [
          {
            'status': '401',
            'title': 'Unauthorized',
            'detail': 'Authentication is required.',
          },
        ],
      }, 401);

      expect(e.type, ApiErrorType.unauthorized);
      expect(e.message, 'Tu sesión expiró. Inicia sesión nuevamente.');
    },
  );
}
