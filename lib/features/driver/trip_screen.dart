import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/placeholder_screen.dart';

class TripScreen extends StatelessWidget {
  const TripScreen({super.key});

  void _onTabTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/driver/home');
        return;
      case 1:
        Navigator.pushReplacementNamed(context, '/driver/routes');
        return;
      case 2:
        return; // already on Trip
      case 3:
        Navigator.pushReplacementNamed(context, '/driver/account');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: 'Recorrido activo',
      icon: Icons.alt_route_outlined,
      subtitle: 'Aquí verás el recorrido en curso.',
      color: SmartBusColors.azulPrincipal,
      onBack: () => Navigator.pushReplacementNamed(context, '/driver/home'),
      bottomNavigationBar: DriverBottomNav(
        currentIndex: 2,
        onTap: (index) => _onTabTap(context, index),
      ),
    );
  }
}
