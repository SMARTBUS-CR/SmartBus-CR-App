import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/placeholder_screen.dart';
import '../auth/services/auth_service.dart';

/// Driver "My account" placeholder — pending wiring to the real profile
/// (data, assigned unit, sign out, etc.).
class DriverAccountScreen extends StatelessWidget {
  const DriverAccountScreen({super.key});

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
    return PlaceholderScreen(
      title: 'Mi Cuenta',
      icon: Icons.person_outline,
      subtitle: 'Aquí verás tu perfil de conductor.',
      color: SmartBusColors.azulPrincipal,
      onBack: () => Navigator.pushReplacementNamed(context, '/driver/home'),
      bottomNavigationBar: DriverBottomNav(
        currentIndex: 3,
        onTap: (index) => _onTabTap(context, index),
      ),
      footer: Padding(
        padding: const EdgeInsets.all(20),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            minimumSize: const Size(double.infinity, 48),
          ),
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
          onPressed: () async {
            await AuthService().logout();
            if (context.mounted) {
              Navigator.pushReplacementNamed(context, '/login');
            }
          },
        ),
      ),
    );
  }
}
