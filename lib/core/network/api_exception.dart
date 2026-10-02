/// Categories of network / API error, already translated into something the UI
/// can act on.
enum ApiErrorType {
  /// Invalid credentials during login (wrong email or password).
  badCredentials,

  /// The account is valid but its role cannot use this app
  /// (only passengers and drivers are allowed).
  roleNotAllowed,

  /// 400 — the backend rejected the request (e.g. wrong or expired reset code).
  /// [ApiException.message] carries the backend message.
  badRequest,

  /// 401 — token missing, invalid or expired.
  unauthorized,

  /// 403 — user is authenticated but not allowed.
  forbidden,

  /// 403 with code `email_not_verified` — valid credentials, but the email has
  /// not been verified yet. The UI should offer to verify it.
  emailNotVerified,

  /// 404 — resource not found.
  notFound,

  /// 422 — validation error on the submitted data.
  /// See [ApiException.fieldErrors] for the errors of each field.
  validation,

  /// 429 — too many requests in a short window (backend throttling).
  tooManyRequests,

  /// 500 — internal server error.
  serverError,

  /// 502 / 503 / 504 — service (or Gateway) unavailable.
  serviceUnavailable,

  /// No internet connection.
  noConnection,

  /// The request took too long.
  timeout,

  /// Any other case.
  unknown,
}

/// Single exception type for the network layer.
///
/// [message] is always a **user-friendly, Spanish, ready-to-display** text.
/// It never contains technical details (stack traces, raw bodies).
class ApiException implements Exception {
  const ApiException(
    this.type,
    this.message, {
    this.statusCode,
    this.fieldErrors = const {},
    this.code,
  });

  final ApiErrorType type;
  final String message;
  final int? statusCode;

  /// Machine-readable error code sent by the backend (`errors[0].code`),
  /// e.g. `email_not_verified`. `null` when the backend sends none.
  final String? code;

  /// Validation errors per field (422), e.g.
  /// `{'email': ['El correo ya está registrado.']}`. Empty for other errors.
  ///
  /// Keys are the request field names (`name`, `email`, `password`, `code`, …),
  /// so a form can show each message under its own input.
  final Map<String, List<String>> fieldErrors;

  static const noConnection = ApiException(
    ApiErrorType.noConnection,
    'Sin conexión a Internet.',
  );

  static const timeout = ApiException(
    ApiErrorType.timeout,
    'La conexión tardó demasiado. Inténtalo nuevamente.',
  );

  static const roleNotAllowed = ApiException(
    ApiErrorType.roleNotAllowed,
    'Esta aplicación es solo para pasajeros y conductores.',
  );

  /// Builds the exception from an HTTP error status code.
  ///
  /// [serverMessage] is the backend message, used only when it is safe to show
  /// (400, 422 and known 403 codes). [fieldErrors] are the per-field
  /// validation errors (422). [errorCode] is the backend `errors[0].code`.
  factory ApiException.fromStatus(
    int status, {
    String? serverMessage,
    Map<String, List<String>> fieldErrors = const {},
    String? errorCode,
  }) {
    switch (status) {
      case 400:
        return ApiException(
          ApiErrorType.badRequest,
          serverMessage ?? 'No se pudo completar la solicitud.',
          statusCode: 400,
        );
      case 401:
        return const ApiException(
          ApiErrorType.unauthorized,
          'Tu sesión expiró. Inicia sesión nuevamente.',
          statusCode: 401,
        );
      case 403 when errorCode == 'email_not_verified':
        return ApiException(
          ApiErrorType.emailNotVerified,
          serverMessage ?? 'Debes verificar tu correo antes de iniciar sesión.',
          statusCode: 403,
          code: errorCode,
        );
      case 403:
        return const ApiException(
          ApiErrorType.forbidden,
          'No tienes autorización para acceder a este recurso.',
          statusCode: 403,
        );
      case 404:
        return const ApiException(
          ApiErrorType.notFound,
          'No se encontró el recurso solicitado.',
          statusCode: 404,
        );
      case 422:
        return ApiException(
          ApiErrorType.validation,
          serverMessage ?? 'Revisa los datos ingresados.',
          statusCode: 422,
          fieldErrors: fieldErrors,
        );
      case 429:
        return const ApiException(
          ApiErrorType.tooManyRequests,
          'Demasiados intentos. Espera un momento e inténtalo de nuevo.',
          statusCode: 429,
        );
      case 500:
        return const ApiException(
          ApiErrorType.serverError,
          'Ocurrió un error en el servidor. Inténtalo más tarde.',
          statusCode: 500,
        );
      case 502:
      case 503:
      case 504:
        return ApiException(
          ApiErrorType.serviceUnavailable,
          'El servicio no está disponible. Inténtalo nuevamente.',
          statusCode: status,
        );
      default:
        return ApiException(
          ApiErrorType.unknown,
          'Ocurrió un error inesperado. Inténtalo nuevamente.',
          statusCode: status,
        );
    }
  }

  @override
  String toString() => 'ApiException($type, status: $statusCode): $message';
}
