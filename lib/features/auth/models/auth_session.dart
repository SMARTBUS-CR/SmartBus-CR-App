import 'auth_user.dart';

/// Authenticated session produced by a successful login.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.user,
    this.expiresAt,
  });

  /// Access token (`meta.access_token`). Used as `Bearer <token>`.
  final String accessToken;

  /// Token type (`meta.token_type`, usually `Bearer`).
  final String tokenType;

  /// Token expiry (`meta.expires_at`), if the backend sends it.
  final DateTime? expiresAt;

  /// Authenticated user, with their roles.
  final AuthUser user;
}
