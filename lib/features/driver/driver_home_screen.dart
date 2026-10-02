import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/smartbus_header.dart';

/// Driver home ("Inicio" tab): overview of the day plus the entry point to
/// start a trip. "Iniciar recorrido" takes the driver to the "Recorrido" tab
/// ([TripScreen]), where the GPS transmission is actually started.
///
/// Uses the shared [SmartBusHeader] (driver variant), like every Driver tab.
class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  void _onTabTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        return; // already on Home
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
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      bottomNavigationBar: DriverBottomNav(
        currentIndex: 0,
        onTap: (index) => _onTabTap(context, index),
      ),
      body: Column(
        children: [
          const SmartBusHeader(
            title: 'Mi ruta del día',
            type: SmartBusUserType.driver,
          ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: SmartBusColors.blanco,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.directions_bus_outlined,
                          size: 64,
                          color: SmartBusColors.azulPrincipal.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Listo para tu recorrido',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Al iniciar, se enviará la ubicación del autobús '
                          'durante todo el recorrido.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 28),
                        GradientButton(
                          label: 'Iniciar recorrido',
                          icon: Icons.play_arrow_rounded,
                          onPressed: () => Navigator.pushReplacementNamed(
                            context,
                            '/driver/trip',
                            arguments: {'autoStart': true},
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
