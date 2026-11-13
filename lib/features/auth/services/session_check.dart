import '../../../core/network/api_exception.dart';
import 'auth_service.dart';

/// Whether the session really expired; see [confirmSessionExpired].
typedef SessionExpiryCheck = Future<bool> Function();

/// A `401` from another service is **not** proof that the session expired.
///
/// The GPS service asks the Gateway who owns the token with a 5 s limit; when
/// the Gateway is slow (Render: 2–4 s per request, more on a spike) or fails,
/// it answers `401` although the token is fine. Treating that as "session
/// expired" sent the driver to Login in the middle of a trip.
///
/// So before signing out, the app asks the Authentication Service itself
/// (`GET /auth/user`): only **its** `401` means the token is no longer
/// valid. A network error, timeout or 5xx means "could not check": the
/// session is kept and the caller tries again later.
Future<bool> confirmSessionExpired() async {
  try {
    await AuthService().fetchCurrentUser();
    return false; // the token works
  } on ApiException catch (e) {
    return e.type == ApiErrorType.unauthorized;
  } catch (_) {
    return false;
  }
}
