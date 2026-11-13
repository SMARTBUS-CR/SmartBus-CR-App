import 'package:flutter/material.dart';

import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/profile_details.dart';
import '../auth/services/auth_service.dart';
import '../trip_tracking/services/active_trip_tracking.dart';

/// Driver "Mi Cuenta" tab: read-only profile of the signed-in driver.
///
/// Driver accounts are created and maintained in the admin panel, so nothing
/// can be edited here. Loading, 401 and retry handling live in
/// [ProfileDetails].
class DriverAccountScreen extends StatelessWidget {
  const DriverAccountScreen({super.key, this.authService, this.sessionStore});

  static const readOnlyNotice =
      'Para actualizar tus datos, contacta al administrador de tu empresa.';

  /// Injectable for tests; defaults to a real [AuthService].
  final AuthService? authService;

  /// Injectable for tests; defaults to a real [SecureSessionStore].
  final SecureSessionStore? sessionStore;

  void _onTabTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/driver/home');
        return;
      case 1:
        Navigator.pushReplacementNamed(context, '/driver/routes');
        return;
      case 2:
        Navigator.pushReplacementNamed(context, '/driver/trip');
        return;
      case 3:
        return; // already on My account
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProfileDetails(
      color: SmartBusColors.azulPrincipal,
      role: 'driver',
      homeRoute: '/driver/home',
      readOnlyNotice: readOnlyNotice,
      authService: authService,
      sessionStore: sessionStore,
      // Logging out (or an expired session) ends the GPS of a running trip.
      onSignOut: ActiveTripTracking.stop,
      bottomNavigationBar: DriverBottomNav(
        currentIndex: 3,
        onTap: (index) => _onTabTap(context, index),
      ),
    );
  }
}
