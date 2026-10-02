import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Global bottom navigation bar for the Passenger flow.
///
/// 3 tabs: Home, My trips, Account. It does not handle navigation itself: the
/// screen using it decides what to do in [onTap] (switch tab, navigate to
/// another route, etc.).
class PassengerBottomNav extends StatelessWidget {
  const PassengerBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: SmartBusColors.verdePasajero.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: SmartBusColors.verdePasajero),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number,
                color: SmartBusColors.verdePasajero),
            label: 'Mis viajes',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon:
                Icon(Icons.person, color: SmartBusColors.verdePasajero),
            label: 'Cuenta',
          ),
        ],
      ),
    );
  }
}
