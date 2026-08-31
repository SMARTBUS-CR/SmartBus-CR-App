import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/passenger_bottom_nav.dart';
import '../../widgets/placeholder_screen.dart';

class PassengerHomeScreen extends StatelessWidget {
  const PassengerHomeScreen({super.key});

  void _onTabTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        return; // ya estamos en Inicio
      case 1:
        Navigator.pushReplacementNamed(context, '/passenger/trips');
        return;
      case 2:
        Navigator.pushReplacementNamed(context, '/passenger/account');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: 'Inicio',
      icon: Icons.home_outlined,
      subtitle: 'Aquí verás tus rutas cercanas y el mapa principal.',
      color: SmartBusColors.verdeMenta,
      bottomNavigationBar: PassengerBottomNav(
        currentIndex: 0,
        onTap: (index) => _onTabTap(context, index),
      ),
    );
  }
}
