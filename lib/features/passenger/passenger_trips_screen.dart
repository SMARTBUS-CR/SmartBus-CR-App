import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/passenger_bottom_nav.dart';
import '../../widgets/placeholder_screen.dart';

/// Passenger "My trips" placeholder — pending wiring to the real trip history.
class PassengerTripsScreen extends StatelessWidget {
  const PassengerTripsScreen({super.key});

  void _onTabTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/passenger/home');
        return;
      case 1:
        return; // already on My trips
      case 2:
        Navigator.pushReplacementNamed(context, '/passenger/account');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: 'Mis Viajes',
      icon: Icons.confirmation_number_outlined,
      subtitle: 'Aquí verás tu historial de viajes.',
      color: SmartBusColors.verdeMenta,
      onBack: () => Navigator.pushReplacementNamed(context, '/passenger/home'),
      bottomNavigationBar: PassengerBottomNav(
        currentIndex: 1,
        onTap: (index) => _onTabTap(context, index),
      ),
    );
  }
}
