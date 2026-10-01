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

  /// Base URL for the **GPS / trip-tracking** endpoints.
  ///
  /// Defaults to [gatewayBaseUrl], so in production everything goes through the
  /// same Gateway. While the GPS service is **not deployed yet**, point this at
  /// a Gateway running on your machine and leave auth on the remote one:
  ///
  /// ```
  /// flutter run \
  ///   --dart-define=GPS_GATEWAY_URL=http://192.168.1.100:8000/api
  /// ```
  ///
  /// (Use your PC's LAN IP for a physical device, or `10.0.2.2` for the Android
  /// emulator. Cleartext HTTP is already allowed in debug builds.)
  static const String gpsBaseUrl = String.fromEnvironment(
    'GPS_GATEWAY_URL',
    defaultValue: gatewayBaseUrl,
  );

  /// Value for the `Accept-Language` header (backend supports: en | es).
  static const String language = String.fromEnvironment(
    'API_LANGUAGE',
    defaultValue: 'es',
  );

  /// Maximum time to wait for a response. Render's free tier can take several
  /// seconds to "wake up" after a period of inactivity.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// How often the driver's GPS position is sent during a trip (issue-4).
  ///
  /// The default (5 s) targets production. A **local** Gateway + GPS service
  /// (two single-threaded `php artisan serve` processes) cannot keep up with
  /// that cadence, so raise it while testing:
  ///   flutter run --dart-define=GPS_INTERVAL_SECONDS=20
  static const int gpsIntervalSeconds = int.fromEnvironment(
    'GPS_INTERVAL_SECONDS',
    defaultValue: 5,
  );

  // --- Microservice identifiers (first path segment of the proxy) -----------
  static const String authService = 'auth';
  static const String gpsService = 'gps';

  // --- Routes through the Gateway -----------------------------------------
  static Uri _uri(String path, [Map<String, dynamic>? query]) => Uri.parse(
        '$gatewayBaseUrl/$path',
      ).replace(queryParameters: query);

  /// Same as [_uri] but against [gpsBaseUrl] (may be a local Gateway).
  static Uri _gpsUri(String path, [Map<String, dynamic>? query]) => Uri.parse(
        '$gpsBaseUrl/$path',
      ).replace(queryParameters: query);

  /// POST — sign in. Equivalent to the Auth service `POST /login`.
  /// `include=roles` embeds the role value/label in the JSON:API response.
  static Uri authLogin() => _uri('$authService/login', {'include': 'roles'});

  /// POST — passenger sign-up. Auth service `POST /register/passenger`.
  /// Returns the same JSON:API document as [authLogin] (user + token).
  static Uri authRegisterPassenger() =>
      _uri('$authService/register/passenger', {'include': 'roles'});

  /// POST — sends a 6-digit password reset code to the email.
  /// Auth service `POST /password/forgot`.
  static Uri authPasswordForgot() => _uri('$authService/password/forgot');

  /// POST — sets a new password with the emailed code.
  /// Auth service `POST /password/reset`.
  static Uri authPasswordReset() => _uri('$authService/password/reset');

  /// GET — authenticated user profile (the Gateway validates the token).
  /// `include=roles` embeds the roles, same as [authLogin].
  static Uri authUser() => _uri('$authService/user', {'include': 'roles'});

  /// POST — sign out (invalidates the token in the Gateway and the Auth service).
  static Uri authLogout() => _uri('$authService/logout');

  /// POST — store one GPS reading of a trip. GPS service `POST /locations`.
  static Uri gpsLocations() => _gpsUri('$gpsService/locations');

  /// GET — latest known location of a trip. GPS service `GET /trips/{id}/location`.
  static Uri gpsTripLocation(String tripId) =>
      _gpsUri('$gpsService/trips/$tripId/location');
}
