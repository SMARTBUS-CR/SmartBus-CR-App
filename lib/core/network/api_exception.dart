/// Categories of network / API error, already translated into something the UI
/// can act on.
enum ApiErrorType {
  /// Invalid credentials during login (wrong email or password).
  badCredentials,

  /// 401 — token missing, invalid or expired.
  unauthorized,

  /// 403 — user is authenticated but not allowed.
  forbidden,

  /// 404 — resource not found.
  notFound,

  /// 422 — validation error on the submitted data.
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
  const ApiException(this.type, this.message, {this.statusCode});

  final ApiErrorType type;
  final String message;
  final int? statusCode;

  static const noConnection = ApiException(
    ApiErrorType.noConnection,
    'Sin conexión a Internet.',
  );

  static const timeout = ApiException(
    ApiErrorType.timeout,
    'La conexión tardó demasiado. Inténtalo nuevamente.',
  );

  /// Builds the exception from an HTTP error status code.
  /// [serverMessage] is the backend message, used only when it is safe to show
  /// (e.g. validation errors).
  factory ApiException.fromStatus(int status, {String? serverMessage}) {
    switch (status) {
      case 401:
        return const ApiException(
          ApiErrorType.unauthorized,
          'Tu sesión expiró. Inicia sesión nuevamente.',
          statusCode: 401,
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
