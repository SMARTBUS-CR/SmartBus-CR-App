import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_session_store.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';

/// Authentication service for SmartBus Global.
///
/// Everything goes through the **API Gateway** (`ApiClient` already has it as
/// the base URL). The app never talks to the Auth microservice directly.
///
/// Ready for the rest of the features: once `/trips`, `/gps`, etc. exist, their
/// services reuse the same [ApiClient] and the stored token is attached
/// automatically.
class AuthService {
  AuthService({ApiClient? client, SecureSessionStore? sessionStore})
      : _client = client ?? ApiClient(),
        _session = sessionStore ?? SecureSessionStore();

  final ApiClient _client;
  final SecureSessionStore _session;

  /// Signs in: `POST {gateway}/auth/login`.
  ///
  /// On success it stores the token and the user (with their roles) in secure
  /// storage. Throws [ApiException] with a user-friendly message on failure.
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

    await _session.saveToken(token, tokenType: tokenType);
    await _session.saveUser(user.toJson());

    return AuthSession(
      accessToken: token,
      tokenType: tokenType,
      user: user,
      expiresAt: DateTime.tryParse((meta['expires_at'] ?? '').toString()),
    );
  }

  /// Validates the token and retrieves the profile: `GET {gateway}/auth/user`.
  ///
  /// The Gateway returns `{id, email, name}` without roles, so the roles stored
  /// at login are kept. Throws [ApiException] if the token is not valid.
  Future<AuthUser> fetchCurrentUser() async {
    final stored = await _session.readUser();
    final fallbackRoles =
        stored != null ? AuthUser.fromStorage(stored).roles : const <AuthRole>[];

    final body = await _client.get(ApiConfig.authUser());
    final user =
        AuthUser.fromGatewayProfile(body, fallbackRoles: fallbackRoles);

    await _session.saveUser(user.toJson());
    return user;
  }

  /// On app start: tries to restore the stored session.
  ///
  /// - No stored token → `null`.
  /// - Valid token → authenticated user.
  /// - Invalid / expired token (401/403) → clears the session and returns `null`.
  /// - Network or server failure → keeps the session with local data so the user
  ///   is not kicked out over a temporary connectivity issue.
  Future<AuthUser?> restoreSession() async {
    if (!await _session.hasSession()) return null;

    try {
      return await fetchCurrentUser();
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.unauthorized ||
          e.type == ApiErrorType.forbidden) {
        await _session.clear();
        return null;
      }
      final stored = await _session.readUser();
      return stored != null ? AuthUser.fromStorage(stored) : null;
    }
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

  Future<bool> hasSession() => _session.hasSession();
}
