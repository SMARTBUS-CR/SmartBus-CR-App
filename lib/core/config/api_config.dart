/// Central network configuration for SmartBus Global.
///
/// The app **only** knows about the API Gateway. The Gateway exposes
/// `/{service}/{path}` as a reverse proxy, so only the prefix of each
/// microservice is needed here (`auth`, and later `trips`, `gps`, `eta`, …) —
/// never the internal service URLs.
///
/// The URL can be swapped per environment without touching code:
///   flutter run --dart-define=API_GATEWAY_URL=https://smartbus-api-gateway.onrender.com/api
class ApiConfig {
  ApiConfig._();

  /// Base URL of the API Gateway — the single entry point of the app.
  ///
  /// The **dev** environment is used for now: the production Gateway
  /// (`https://smartbus-api-gateway.onrender.com/api`) is not operational yet.
  /// Change the default (or pass `--dart-define=API_GATEWAY_URL=...`) once
  /// production is ready.
  static const String gatewayBaseUrl = String.fromEnvironment(
    'API_GATEWAY_URL',
    defaultValue: 'https://smartbus-api-gateway-dev.onrender.com/api',
  );

  /// Value for the `Accept-Language` header (backend supports: en | es).
  static const String language = String.fromEnvironment(
    'API_LANGUAGE',
    defaultValue: 'es',
  );

  /// Maximum time to wait for a response. Render's free tier can take several
  /// seconds to "wake up" after a period of inactivity.
  static const Duration requestTimeout = Duration(seconds: 30);

  // --- Microservice identifiers (first path segment of the proxy) -----------
  static const String authService = 'auth';

  // --- Routes through the Gateway -----------------------------------------
  static Uri _uri(String path, [Map<String, dynamic>? query]) => Uri.parse(
        '$gatewayBaseUrl/$path',
      ).replace(queryParameters: query);

  /// POST — sign in. Equivalent to the Auth service `POST /login`.
  /// `include=roles` embeds the role value/label in the JSON:API response.
  static Uri authLogin() => _uri('$authService/login', {'include': 'roles'});

  /// GET — authenticated user profile (the Gateway validates the token).
  static Uri authUser() => _uri('$authService/user');

  /// POST — sign out (invalidates the token in the Gateway and the Auth service).
  static Uri authLogout() => _uri('$authService/logout');
}
