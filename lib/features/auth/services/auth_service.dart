import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_session_store.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../models/pending_verification.dart';
import '../models/profile_update.dart';

/// Authentication service for SmartBus Global.
///
/// Everything goes through the **API Gateway** (`ApiClient` already has it as
/// the base URL). The app never talks to the Auth microservice directly.
///
/// Screens only call these methods: routes, JSON:API parsing, token storage and
/// error translation are handled here. Every failure is an [ApiException] with
/// a ready-to-display Spanish message (see `lib/README.md`, "AuthService
/// contract").
///
/// Only **passengers and drivers** can use the app: any other role is signed
/// out and rejected with [ApiErrorType.roleNotAllowed].
class AuthService {
  AuthService({ApiClient? client, SecureSessionStore? sessionStore})
      : _session = sessionStore ?? SecureSessionStore(),
        _client = client ?? ApiClient(sessionStore: sessionStore);

  final ApiClient _client;
  final SecureSessionStore _session;

  /// Signs in: `POST {gateway}/auth/login?include=roles`.
  ///
  /// On success it stores the token and the user (with their roles) in secure
  /// storage.
  ///
  /// Throws [ApiException]:
  /// - [ApiErrorType.badCredentials] — wrong email or password.
  /// - [ApiErrorType.emailNotVerified] — right password, email not verified yet
  ///   (offer [resendVerificationCode] + [verifyEmail]).
  /// - [ApiErrorType.roleNotAllowed] — the account is not a passenger or driver.
  /// - [ApiErrorType.tooManyRequests] — too many attempts.
  /// - [ApiErrorType.serviceUnavailable] / network errors.
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    Map<String, dynamic> body;
    try {
      body = await _client.post(
        ApiConfig.authLogin(),
        body: {'email': email, 'password': password},
      );
    } on ApiException catch (e) {
      // 401 / 422 during login = wrong credentials for the user.
      if (e.type == ApiErrorType.validation ||
          e.type == ApiErrorType.unauthorized) {
        throw const ApiException(
          ApiErrorType.badCredentials,
          'Correo o contraseña incorrectos.',
        );
      }
      // 404 / 502 during login = the endpoint is not available on the Gateway.
      if (e.type == ApiErrorType.notFound ||
          e.type == ApiErrorType.serviceUnavailable) {
        throw const ApiException(
          ApiErrorType.serviceUnavailable,
          'El servicio de inicio de sesión no está disponible en este momento.',
        );
      }
      rethrow;
    }

    return _startSession(body);
  }

  /// Passenger sign-up: `POST {gateway}/auth/register/passenger?include=roles`.
  ///
  /// The backend creates a **passenger** and emails a 6-digit code, but does
  /// **not** sign them in: nothing is stored. Continue with [verifyEmail].
  ///
  /// Throws [ApiException]:
  /// - [ApiErrorType.validation] — see [ApiException.fieldErrors]
  ///   (`name`, `email`, `password`).
  /// - [ApiErrorType.tooManyRequests] / network errors.
  Future<PendingVerification> registerPassenger({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final body = await _client.post(
      ApiConfig.authRegisterPassenger(),
      body: {
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
      },
    );

    final data = body['data'];
    final attributes = data is Map ? data['attributes'] : null;
    final registeredEmail = attributes is Map ? attributes['email'] : null;

    return PendingVerification(
      email: registeredEmail is String && registeredEmail.isNotEmpty
          ? registeredEmail
          : email,
      message: _metaMessage(
        body,
        fallback: 'Te enviamos un código de verificación a tu correo.',
      ),
    );
  }

  /// Verifies the email with the 6-digit code and **signs the user in**:
  /// `POST {gateway}/auth/email/verify?include=roles`.
  ///
  /// On success the token and the user are stored exactly like [login].
  ///
  /// Throws [ApiException]:
  /// - [ApiErrorType.badRequest] — wrong code, expired code (15 min) or too
  ///   many wrong attempts (backend message says which).
  /// - [ApiErrorType.validation] — see [ApiException.fieldErrors]
  ///   (`email`, `code`).
  /// - [ApiErrorType.roleNotAllowed] — the account is not a passenger or driver.
  /// - [ApiErrorType.tooManyRequests] / network errors.
  Future<AuthSession> verifyEmail({
    required String email,
    required String code,
  }) async {
    final body = await _client.post(
      ApiConfig.authEmailVerify(),
      body: {'email': email, 'code': code},
    );

    return _startSession(body);
  }

  /// Sends a new email verification code:
  /// `POST {gateway}/auth/email/resend`.
  ///
  /// The backend always answers with the same message (it does not reveal
  /// whether the email exists or is already verified). Returns that message.
  ///
  /// Throws [ApiException]:
  /// - [ApiErrorType.tooManyRequests] — more than 3 requests per minute.
  /// - [ApiErrorType.validation] — `fieldErrors['email']`.
  /// - Network errors.
  Future<String> resendVerificationCode(String email) async {
    final body = await _client.post(
      ApiConfig.authEmailResend(),
      body: {'email': email},
    );

    return _metaMessage(
      body,
      fallback: 'Te enviamos un código de verificación a tu correo.',
    );
  }

  /// Sends a 6-digit password reset code by email:
  /// `POST {gateway}/auth/password/forgot`.
  ///
  /// Returns the backend message to show to the user.
  ///
  /// Throws [ApiException]:
  /// - [ApiErrorType.validation] — `fieldErrors['email']` (invalid or unknown email).
  /// - [ApiErrorType.tooManyRequests] — too many codes requested.
  /// - Network errors.
  Future<String> sendResetCode(String email) async {
    final body = await _client.post(
      ApiConfig.authPasswordForgot(),
      body: {'email': email},
    );

    return _metaMessage(body, fallback: 'Te enviamos un código a tu correo.');
  }

  /// Sets a new password with the emailed code:
  /// `POST {gateway}/auth/password/reset`.
  ///
  /// The backend signs the user out of every device, so they must log in again.
  /// Returns the backend message to show to the user.
  ///
  /// Throws [ApiException]:
  /// - [ApiErrorType.badRequest] — wrong or expired code (backend message).
  /// - [ApiErrorType.validation] — see [ApiException.fieldErrors]
  ///   (`email`, `code`, `password`).
  /// - [ApiErrorType.tooManyRequests] / network errors.
  Future<String> resetPassword({
    required String email,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    final body = await _client.post(
      ApiConfig.authPasswordReset(),
      body: {
        'email': email,
        'code': code,
        'password': password,
        'password_confirmation': passwordConfirmation,
      },
    );

    return _metaMessage(body, fallback: 'Tu contraseña se actualizó.');
  }

  /// Validates the token and retrieves the profile:
  /// `GET {gateway}/auth/user?include=roles`.
  ///
  /// The refreshed user is stored in secure storage.
  /// Throws [ApiException] ([ApiErrorType.unauthorized] if the token is not valid).
  Future<AuthUser> fetchCurrentUser() async {
    final body = await _client.get(ApiConfig.authUser());
    var user = AuthUser.fromJsonApi(body);

    // Defensive: keep the roles stored at login if the response has none.
    if (user.roles.isEmpty) {
      final stored = await _session.readUser();
      if (stored != null) {
        user = user.copyWith(roles: AuthUser.fromStorage(stored).roles);
      }
    }

    await _session.saveUser(user.toJson());
    return user;
  }

  /// The passenger updates their own profile:
  /// `PATCH {gateway}/auth/user?include=roles`.
  ///
  /// Only the non-null fields are sent; pass only what changed.
  /// [currentPassword] is required by the backend when [email] is sent.
  ///
  /// - Name only → the updated user is stored and the session stays as is.
  /// - Email (with or without name) → the backend marks the new address as
  ///   **unverified**, so the stored token stops working. The local session is
  ///   cleared and [ProfileUpdate.requiresEmailVerification] is `true`: continue
  ///   with [resendVerificationCode] + [verifyEmail] (which signs in again).
  ///
  /// Throws [ApiException]:
  /// - [ApiErrorType.validation] — see [ApiException.fieldErrors]
  ///   (`name`, `email` — e.g. already registered —, `current_password`).
  /// - [ApiErrorType.unauthorized] — the token expired.
  /// - [ApiErrorType.forbidden] — the account is not a passenger.
  /// - [ApiErrorType.tooManyRequests] — more than 5 updates per minute.
  /// - Network errors.
  Future<ProfileUpdate> updateProfile({
    String? name,
    String? email,
    String? currentPassword,
  }) async {
    assert(name != null || email != null, 'Nothing to update');

    final body = await _client.patch(
      ApiConfig.authUpdateProfile(),
      body: {
        'name': ?name,
        'email': ?email,
        'current_password': ?currentPassword,
      },
    );

    var user = AuthUser.fromJsonApi(body);
    // Defensive: keep the stored roles if the response has none.
    if (user.roles.isEmpty) {
      final stored = await _session.readUser();
      if (stored != null) {
        user = user.copyWith(roles: AuthUser.fromStorage(stored).roles);
      }
    }

    final requiresEmailVerification = email != null;
    if (requiresEmailVerification) {
      // Unverified email: every protected route rejects this token now.
      await _session.clear();
    } else {
      await _session.saveUser(user.toJson());
    }

    return ProfileUpdate(
      user: user,
      requiresEmailVerification: requiresEmailVerification,
    );
  }

  /// The passenger changes their own password:
  /// `PUT {gateway}/auth/user/password`.
  ///
  /// The user stays signed in on this device; the backend closes the sessions
  /// on other devices. Returns the backend message to show.
  ///
  /// Throws [ApiException]:
  /// - [ApiErrorType.validation] — see [ApiException.fieldErrors]
  ///   (`current_password` wrong, `password` weak / compromised / same as the
  ///   current one / not confirmed).
  /// - [ApiErrorType.unauthorized] — the token expired.
  /// - [ApiErrorType.forbidden] — the account is not a passenger.
  /// - [ApiErrorType.tooManyRequests] — more than 5 changes per minute.
  /// - Network errors.
  Future<String> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    final body = await _client.put(
      ApiConfig.authChangePassword(),
      body: {
        'current_password': currentPassword,
        'password': password,
        'password_confirmation': passwordConfirmation,
      },
    );

    return _metaMessage(body, fallback: 'Tu contraseña se actualizó.');
  }

  /// On app start: tries to restore the stored session.
  ///
  /// - No stored token → `null`.
  /// - Valid token → authenticated user.
  /// - Invalid / expired token (401/403) → clears the session and returns `null`.
  /// - Role not allowed in the app → signs out and returns `null`.
  /// - Network or server failure → keeps the session with local data so the user
  ///   is not kicked out over a temporary connectivity issue.
  Future<AuthUser?> restoreSession() async {
    if (!await _session.hasSession()) return null;

    AuthUser? user;
    try {
      user = await fetchCurrentUser();
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.unauthorized ||
          e.type == ApiErrorType.forbidden) {
        await _session.clear();
        return null;
      }
      final stored = await _session.readUser();
      user = stored != null ? AuthUser.fromStorage(stored) : null;
    }

    if (user != null && !user.isAllowedInApp) {
      await logout();
      return null;
    }
    return user;
  }

  /// Signs out: `POST {gateway}/auth/logout` + clears storage.
  ///
  /// The local session is always cleared, even if the server call fails.
  Future<void> logout() async {
    try {
      await _client.post(ApiConfig.authLogout());
    } on ApiException {
      // Intentionally ignored: the local session must be cleared regardless.
    } finally {
      await _session.clear();
    }
  }

  /// Soft-deletes the signed-in **passenger's** own account:
  /// `DELETE {gateway}/auth/user` with `current_password` and
  /// `confirm_deletion: true`.
  ///
  /// The backend marks the account as deleted (the data stays in the database
  /// but the user can no longer log in) and revokes every token, so on success
  /// the local session is cleared (no `POST /auth/logout`: the token is already
  /// gone). Returns the backend message to show.
  ///
  /// Throws [ApiException]:
  /// - [ApiErrorType.validation] — `fieldErrors['current_password']` (wrong
  ///   password). The session is kept so the user can try again.
  /// - [ApiErrorType.unauthorized] — the token expired; the local session is
  ///   cleared.
  /// - [ApiErrorType.forbidden] / [ApiErrorType.emailNotVerified] — the
  ///   account cannot be deleted (not only a passenger, or email not verified).
  /// - [ApiErrorType.tooManyRequests] — more than 5 attempts per minute.
  /// - Network errors.
  Future<String> deleteAccount({required String currentPassword}) async {
    final Map<String, dynamic> body;
    try {
      body = await _client.delete(
        ApiConfig.authDeleteAccount(),
        body: {'current_password': currentPassword, 'confirm_deletion': true},
      );
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.unauthorized) await _session.clear();
      rethrow;
    }

    await _session.clear();
    return _metaMessage(body, fallback: 'Cuenta eliminada correctamente.');
  }

  Future<bool> hasSession() => _session.hasSession();

  // --- Internals ------------------------------------------------------------

  /// Stores the token + user of a login / sign-up response and enforces the
  /// allowed roles (the server session is closed if the role is not allowed).
  Future<AuthSession> _startSession(Map<String, dynamic> body) async {
    final meta = (body['meta'] as Map<String, dynamic>?) ?? const {};
    final token = (meta['access_token'] ?? '').toString();
    if (token.isEmpty) {
      throw const ApiException(
        ApiErrorType.unknown,
        'No se pudo iniciar sesión. Inténtalo nuevamente.',
      );
    }
    final tokenType = (meta['token_type'] ?? 'Bearer').toString();
    final user = AuthUser.fromJsonApi(body);

    // Stored first so logout() can send the token to close the server session.
    await _session.saveToken(token, tokenType: tokenType);
    await _session.saveUser(user.toJson());

    if (!user.isAllowedInApp) {
      await logout();
      throw ApiException.roleNotAllowed;
    }

    return AuthSession(
      accessToken: token,
      tokenType: tokenType,
      user: user,
      expiresAt: DateTime.tryParse((meta['expires_at'] ?? '').toString()),
    );
  }

  /// `meta.message` of a success response, or [fallback].
  String _metaMessage(Map<String, dynamic> body, {required String fallback}) {
    final meta = body['meta'];
    final message = meta is Map ? meta['message'] : null;
    return message is String && message.isNotEmpty ? message : fallback;
  }
}
