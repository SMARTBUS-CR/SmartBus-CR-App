import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Global bottom navigation bar for the Driver flow.
///
/// 4 tabs: Home, My routes, Trip, My account. It does not handle navigation
/// itself: the screen using it decides what to do in [onTap] (switch tab,
/// navigate to another route, etc.).
class DriverBottomNav extends StatelessWidget {
  const DriverBottomNav({
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
        indicatorColor: SmartBusColors.azulPrincipal.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon:
                Icon(Icons.home, color: SmartBusColors.azulPrincipal),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: SmartBusColors.azulPrincipal),
            label: 'Mis rutas',
          ),
          NavigationDestination(
            icon: Icon(Icons.alt_route_outlined),
            selectedIcon:
                Icon(Icons.alt_route, color: SmartBusColors.azulPrincipal),
            label: 'Recorrido',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon:
                Icon(Icons.person, color: SmartBusColors.azulPrincipal),
            label: 'Mi cuenta',
          ),
        ],
      ),
    );
  }
}
