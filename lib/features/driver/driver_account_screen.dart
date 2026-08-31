import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/placeholder_screen.dart';

/// Placeholder de "Mi cuenta" para el conductor — pendiente de conectar
/// con el perfil real (datos, unidad asignada, cierre de sesión, etc.).
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
        return; // ya estamos en Mi cuenta
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
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/login');
          },
        ),
      ),
    );
  }
}
