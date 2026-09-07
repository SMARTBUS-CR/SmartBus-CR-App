import 'models/auth_user.dart';

/// Home route for the role returned by the backend.
///
/// The role is decided by the authenticated backend; this only maps it to the
/// matching screen. Returns `null` when the role does not have a dedicated
/// screen in the app yet (e.g. `admin`), so the UI layer can decide what to do
/// (show a notice and not let them in).
String? homeRouteForUser(AuthUser user) {
  if (user.isDriver) return '/driver/home';
  if (user.isPassenger) return '/passenger/home';
  return null;
}
