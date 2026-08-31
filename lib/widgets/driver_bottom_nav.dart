import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Barra de navegación inferior global para el flujo de Conductor.
///
/// 4 pestañas: Inicio, Mis rutas, Recorrido, Mi cuenta. No maneja
/// navegación por sí misma: la pantalla que la usa decide qué hacer en
/// [onTap] (cambiar de pestaña, navegar a otra ruta, etc.).
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
