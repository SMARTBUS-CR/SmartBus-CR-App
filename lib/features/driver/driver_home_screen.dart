import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/placeholder_screen.dart';

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  void _onTabTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        return; // ya estamos en Inicio
      case 1:
        Navigator.pushReplacementNamed(context, '/driver/routes');
        return;
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
      title: 'Mi ruta del día',
      icon: Icons.home_outlined,
      subtitle: 'Aquí verás el panorama general de tu recorrido.',
      color: SmartBusColors.azulPrincipal,
      bottomNavigationBar: DriverBottomNav(
        currentIndex: 0,
        onTap: (index) => _onTabTap(context, index),
      ),
    );
  }
}
