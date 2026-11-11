import 'package:flutter/material.dart';

import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../../widgets/passenger_bottom_nav.dart';
import '../../widgets/profile_details.dart';
import '../auth/services/auth_service.dart';

/// Passenger "Mi Cuenta" tab: read-only profile of the signed-in user.
///
/// Name, email and password are edited on their own screens ("Editar perfil",
/// "Cambiar contraseña"). Loading, 401 and retry handling live in
/// [ProfileDetails].
///
/// "Eliminar cuenta" is UI only for now: Auth has no self-service deletion
/// endpoint yet (`DELETE /api/users/{user}` requires `users.delete` and
/// rejects deleting yourself), so confirming only shows a notice.
class PassengerAccountScreen extends StatelessWidget {
  const PassengerAccountScreen({
    super.key,
    this.authService,
    this.sessionStore,
  });

  /// Injectable for tests; defaults to a real [AuthService].
  final AuthService? authService;

  /// Injectable for tests; defaults to a real [SecureSessionStore].
  final SecureSessionStore? sessionStore;

  void _onTabTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/passenger/home');
        return;
      case 1:
        Navigator.pushReplacementNamed(context, '/passenger/trips');
        return;
      case 2:
        return; // already on Account
    }
  }

  /// Temporary until the backend supports self-service account deletion.
  void _onDeleteAccount(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Esta función estará disponible pronto.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProfileDetails(
      color: SmartBusColors.verdePasajero,
      role: 'passenger',
      homeRoute: '/passenger/home',
      onDeleteAccount: () => _onDeleteAccount(context),
      onEditProfile: (user) => Navigator.pushNamed(
        context,
        '/passenger/account/edit',
        arguments: user,
      ),
      onChangePassword: () =>
          Navigator.pushNamed(context, '/passenger/account/password'),
      authService: authService,
      sessionStore: sessionStore,
      bottomNavigationBar: PassengerBottomNav(
        currentIndex: 2,
        onTap: (index) => _onTabTap(context, index),
      ),
    );
  }
}
