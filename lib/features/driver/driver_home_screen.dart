import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/gradient_button.dart';

/// Driver home ("Inicio" tab): overview of the day plus the entry point to
/// start a trip. "Iniciar recorrido" takes the driver to the "Recorrido" tab
/// ([TripScreen]), where the GPS transmission is actually started.
///
/// The header mirrors [PlaceholderScreen]: solid [SmartBusColors.azulPrincipal],
/// short app bar and centered title, so every Driver tab looks the same.
class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  static const _headerColor = SmartBusColors.azulPrincipal;

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
      appBar: AppBar(
        backgroundColor: _headerColor,
        elevation: 0,
        toolbarHeight: 40,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: DriverBottomNav(
        currentIndex: 0,
        onTap: (index) => _onTabTap(context, index),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: _headerColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 70),
            alignment: Alignment.center,
            child: const Text(
              'Mi ruta del día',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SmartBusColors.blanco,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -40,
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
                          color: SmartBusColors.azulPrincipal
                              .withValues(alpha: 0.35),
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
