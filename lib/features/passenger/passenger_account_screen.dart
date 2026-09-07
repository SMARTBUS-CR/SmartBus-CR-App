import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/passenger_bottom_nav.dart';
import '../../widgets/placeholder_screen.dart';
import '../auth/services/auth_service.dart';

/// Passenger "Account" placeholder — pending wiring to the real profile
/// (data, sign out, etc.).
class PassengerAccountScreen extends StatelessWidget {
  const PassengerAccountScreen({super.key});

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
    return PlaceholderScreen(
      title: 'Mi Cuenta',
      icon: Icons.person_outline,
      subtitle: 'Aquí verás tu perfil de pasajero.',
      color: SmartBusColors.verdeMenta,
      onBack: () => Navigator.pushReplacementNamed(context, '/passenger/home'),
      bottomNavigationBar: PassengerBottomNav(
        currentIndex: 2,
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
