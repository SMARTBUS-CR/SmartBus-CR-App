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

  /// Base URL for the **Dashboard (operations)** endpoints: routes, buses
  /// running and the driver's trips. Defaults to [gatewayBaseUrl]; point it at
  /// a local Gateway while the `ops` proxy is not deployed:
  ///   --dart-define=OPS_GATEWAY_URL=http://127.0.0.1:8001/api
  static const String opsBaseUrl = String.fromEnvironment(
    'OPS_GATEWAY_URL',
    defaultValue: gatewayBaseUrl,
  );

  /// Value for the `Accept-Language` header (backend supports: en | es).
  static const String language = String.fromEnvironment(
    'API_LANGUAGE',
    defaultValue: 'es',
  );

  /// Maximum time to wait for a response. Render's free tier "wakes up" after a
  /// period of inactivity, and a request may wake **two** services (Gateway +
  /// Auth): a first login measured ~38 s, so 30 s was not enough. Screens show
  /// [SlowRequestHint] while waiting.
  static const Duration requestTimeout = Duration(seconds: 60);

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

  // --- Real time (GPS service, Laravel Reverb — Pusher protocol) -----------
  //
  // The passenger map receives the bus position over a WebSocket. In Render
  // the Gateway's nginx forwards `wss://<gateway>/app/<KEY>` to Reverb, so by
  // default the socket goes to the same host as [gpsBaseUrl].
  //
  // Local test (Gateway with `php artisan serve` has no nginx): point it at
  // Reverb directly:
  //   --dart-define=REVERB_APP_KEY=<key> --dart-define=REVERB_HOST=192.168.1.100
  //   --dart-define=REVERB_PORT=8080 --dart-define=REVERB_SCHEME=ws

  /// `REVERB_APP_KEY` of the GPS service. It is **not** a secret (the secret
  /// never leaves the backend). Empty = no real time: the map falls back to
  /// asking the position every few seconds.
  ///
  /// The default is the key of the **-dev** GPS service on Render (Render →
  /// GPS service -dev → Environment → `REVERB_APP_KEY`), so a plain
  /// `flutter run` has real time against -dev. Override it per environment:
  ///   `--dart-define=REVERB_APP_KEY=...`
  /// (with a local Reverb, pass the key of the local `.env`).
  static const String reverbAppKey = String.fromEnvironment(
    'REVERB_APP_KEY',
    defaultValue: _devReverbAppKey,
  );

  /// TODO: paste here the `REVERB_APP_KEY` of the -dev GPS service on Render.
  static const String _devReverbAppKey = 'd193ac195d39ea68330c';

  /// Empty = the host of [gpsBaseUrl].
  static const String reverbHost = String.fromEnvironment('REVERB_HOST');

  /// `0` = the port of [gpsBaseUrl] (443 / 80 when it has none).
  static const int reverbPort = int.fromEnvironment('REVERB_PORT');

  /// `wss` or `ws`. Empty = `wss` when [gpsBaseUrl] is https, `ws` otherwise.
  static const String reverbScheme = String.fromEnvironment('REVERB_SCHEME');

  /// WebSocket URL of Reverb, or `null` when [reverbAppKey] is not set.
  static Uri? reverbUri() {
    if (reverbAppKey.isEmpty) return null;
    final base = Uri.parse(gpsBaseUrl);
    final scheme = reverbScheme.isNotEmpty
        ? reverbScheme
        : (base.scheme == 'https' ? 'wss' : 'ws');
    final port = reverbPort != 0
        ? reverbPort
        : (base.hasPort ? base.port : (scheme == 'wss' ? 443 : 80));
    return Uri(
      scheme: scheme,
      host: reverbHost.isNotEmpty ? reverbHost : base.host,
      port: port,
      path: '/app/$reverbAppKey',
      queryParameters: const {
        'protocol': '7',
        'client': 'smartbus-flutter',
        'version': '1.0',
        'flash': 'false',
      },
    );
  }

  // --- Microservice identifiers (first path segment of the proxy) -----------
  static const String authService = 'auth';
  static const String gpsService = 'gps';
  static const String opsService = 'ops';

  // --- Routes through the Gateway -----------------------------------------
  static Uri _uri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('$gatewayBaseUrl/$path').replace(queryParameters: query);

  /// Same as [_uri] but against [gpsBaseUrl] (may be a local Gateway).
  static Uri _gpsUri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('$gpsBaseUrl/$path').replace(queryParameters: query);

  /// Same as [_uri] but against [opsBaseUrl] (may be a local Gateway).
  static Uri _opsUri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('$opsBaseUrl/$opsService/$path')
          .replace(queryParameters: query);

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

  /// PATCH — the passenger updates their own name and/or email.
  /// Auth service `PATCH /user`. Returns the updated user, like [authUser].
  static Uri authUpdateProfile() =>
      _uri('$authService/user', {'include': 'roles'});

  /// PUT — the passenger changes their own password (current one required).
  /// Auth service `PUT /user/password`.
  static Uri authChangePassword() => _uri('$authService/user/password');

  /// DELETE — soft-deletes the signed-in passenger's own account and revokes
  /// all of their tokens. Auth service `DELETE /user` (body:
  /// `current_password`, `confirm_deletion`).
  static Uri authDeleteAccount() => _uri('$authService/user');

  /// POST — verify the email with the 6-digit code; logs the user in.
  /// `include=roles` embeds the roles, same as [authLogin].
  static Uri authEmailVerify() =>
      _uri('$authService/email/verify', {'include': 'roles'});

  /// POST — send a new email verification code.
  static Uri authEmailResend() => _uri('$authService/email/resend');

  /// POST — sign out (invalidates the token in the Gateway and the Auth service).
  static Uri authLogout() => _uri('$authService/logout');

  /// POST — store one GPS reading of a trip. GPS service `POST /locations`.
  static Uri gpsLocations() => _gpsUri('$gpsService/locations');

  /// GET — latest known location of a trip. GPS service `GET /trips/{id}/location`.
  static Uri gpsTripLocation(String tripId) =>
      _gpsUri('$gpsService/trips/$tripId/location');

  /// POST — signature for a private real-time channel (`private-trip.{id}`).
  /// GPS service `POST /broadcasting/auth`.
  static Uri gpsBroadcastingAuth() => _gpsUri('$gpsService/broadcasting/auth');

  // --- Dashboard (operations), JSON:API -------------------------------------

  /// GET — trips of the logged-in driver (token). Dashboard `driver/trips`.
  static Uri opsDriverTrips([Map<String, dynamic>? query]) =>
      _opsUri('driver/trips', query);

  /// POST — the assigned driver starts a trip (token).
  static Uri opsTripStart(String tripId) => _opsUri('trips/$tripId/start');

  /// POST — the assigned driver completes a trip (token).
  static Uri opsTripComplete(String tripId) =>
      _opsUri('trips/$tripId/complete');

  /// GET — public route catalogue.
  static Uri opsRoutes([Map<String, dynamic>? query]) =>
      _opsUri('routes', query);

  /// GET — directions (patterns) of a route, with line and stops.
  static Uri opsRoutePatterns(String routeId) =>
      _opsUri('routes/$routeId/patterns');

  /// GET — buses running now on a pattern (public, no driver data).
  static Uri opsPatternTrips(String patternId, [Map<String, dynamic>? query]) =>
      _opsUri('route-patterns/$patternId/trips', query);
}
