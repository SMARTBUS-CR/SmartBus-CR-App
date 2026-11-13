/// Response bodies shaped like the real Auth service responses proxied by the
/// API Gateway (JSON:API, `?include=roles`). Used by the auth unit tests.
library;

const passengerId = '01a0c691-579f-731c-a034-03cc8fe8136f';
const driverId = '01a0c691-6000-731c-a034-03cc8fe8136f';
const adminId = '01a0c691-7000-731c-a034-03cc8fe8136f';

Map<String, dynamic> userDocument({
  String id = passengerId,
  String name = 'Passenger User',
  String email = 'user@passenger.com',
  String role = 'passenger',
  String roleLabel = 'Pasajero',
  String? token,
}) {
  return {
    'data': {
      'id': id,
      'type': 'users',
      'attributes': {
        'name': name,
        'email': email,
        'permissions': <String>[],
        'direct_permissions': <String>[],
      },
      'relationships': {
        'roles': {
          'data': [
            {'id': '4', 'type': 'roles'},
          ],
        },
      },
    },
    'included': [
      {
        'id': '4',
        'type': 'roles',
        'attributes': {'value': role, 'label': roleLabel},
      },
    ],
    if (token != null)
      'meta': {
        'access_token': token,
        'token_type': 'Bearer',
        'expires_at': '2026-10-28T18:48:59+00:00',
      },
  };
}

/// 422 rendered by the Auth service (JSON:API, one error per message).
Map<String, dynamic> validationErrors(Map<String, List<String>> fields) {
  return {
    'errors': [
      for (final entry in fields.entries)
        for (final message in entry.value)
          {
            'status': 422,
            'title': 'Validation Error',
            'detail': message,
            'source': {'pointer': '/data/attributes/${entry.key}'},
          },
    ],
  };
}

/// Non-validation error rendered by the Auth service (400, 401, 429, …).
Map<String, dynamic> jsonApiError(int status, String title, String detail) {
  return {
    'errors': [
      {'status': '$status', 'title': title, 'detail': detail},
    ],
  };
}

Map<String, dynamic> metaMessage(String message) => {
  'meta': {'message': message},
};

/// 201 of `POST /register/passenger` since email verification: the user
/// (unverified) and `meta.verification_required`, but **no token**.
Map<String, dynamic> pendingVerificationDocument({
  String email = 'user@passenger.com',
  String message = 'Te enviamos un código de verificación a tu correo.',
}) {
  final document = userDocument(email: email);
  (document['data']['attributes'] as Map<String, dynamic>)['email_verified'] =
      false;
  return {
    ...document,
    'meta': {'verification_required': true, 'message': message},
  };
}

/// 403 of `POST /login` when the password is right but the email is not
/// verified yet.
Map<String, dynamic> emailNotVerifiedError({
  String detail = 'Debes verificar tu correo antes de iniciar sesión.',
}) {
  return {
    'errors': [
      {
        'status': '403',
        'code': 'email_not_verified',
        'title': 'Prohibido',
        'detail': detail,
      },
    ],
  };
}
