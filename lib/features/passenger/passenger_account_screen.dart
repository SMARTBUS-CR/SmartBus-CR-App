import 'package:flutter/material.dart';

import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../../widgets/passenger_bottom_nav.dart';
import '../../widgets/profile_details.dart';
import '../auth/services/auth_service.dart';

/// Passenger "Mi Cuenta" tab: read-only profile of the signed-in user.
///
/// Loading, 401, retry and "Eliminar cuenta" (soft delete through
/// `DELETE /auth/user`) live in [ProfileDetails].
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

  @override
  Widget build(BuildContext context) {
    return ProfileDetails(
      color: SmartBusColors.verdePasajero,
      role: 'passenger',
      homeRoute: '/passenger/home',
      canDeleteAccount: true,
      authService: authService,
      sessionStore: sessionStore,
      bottomNavigationBar: PassengerBottomNav(
        currentIndex: 2,
        onTap: (index) => _onTabTap(context, index),
      ),
    );
  }
}
