import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/placeholder_screen.dart';

class DriverRoutesScreen extends StatelessWidget {
  const DriverRoutesScreen({super.key});

  void _onTabTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/driver/home');
        return;
      case 1:
        return; // ya estamos en Mis rutas
      case 2:
        Navigator.pushReplacementNamed(context, '/driver/trip');
        return;
      case 3:
        Navigator.pushReplacementNamed(context, '/driver/account');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: 'Mis Rutas',
      icon: Icons.map_outlined,
      subtitle: 'Aquí verás el listado de rutas asignadas.',
      color: SmartBusColors.azulPrincipal,
      onBack: () => Navigator.pushReplacementNamed(context, '/driver/home'),
      bottomNavigationBar: DriverBottomNav(
        currentIndex: 1,
        onTap: (index) => _onTabTap(context, index),
      ),
    );
  }
}
