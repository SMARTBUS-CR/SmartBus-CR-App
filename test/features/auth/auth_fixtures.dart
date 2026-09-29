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
