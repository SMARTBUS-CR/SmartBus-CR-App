import 'auth_user.dart';

/// Result of [AuthService.updateProfile].
class ProfileUpdate {
  const ProfileUpdate({
    required this.user,
    required this.requiresEmailVerification,
  });

  /// User as returned by the backend after the update.
  final AuthUser user;

  /// `true` when the email changed: the backend marks it as unverified, so the
  /// local session was cleared and the new address must be verified with a
  /// 6-digit code (`/verify-email`) to sign in again.
  final bool requiresEmailVerification;
}
