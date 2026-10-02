/// Result of a passenger sign-up: the account exists but its email must be
/// verified (6-digit code sent by email) before the user can log in.
class PendingVerification {
  const PendingVerification({required this.email, required this.message});

  /// Address the code was sent to (the one to verify).
  final String email;

  /// Backend message, ready to display (e.g. "Te enviamos un código…").
  final String message;
}
