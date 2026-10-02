import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/smartbus_header.dart';

class BusTrackingScreen extends StatelessWidget {
  const BusTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      body: Column(
        children: [
          SmartBusHeader(
            title: 'Rastreando tu bus',
            subtitle: 'Ruta 4 · Sarapiquí – Puerto Viejo',
            type: SmartBusUserType.passenger,
            compact: true,
            // Same as the former AppBar: back only when there is a screen
            // to go back to.
            onBack: Navigator.canPop(context)
                ? () => Navigator.pop(context)
                : null,
          ),
          // WHITE CONTENT
          Expanded(
            child: Container(
              decoration: const BoxDecoration(color: SmartBusColors.blanco),
              child: Column(
                children: [
                  // Live bus position map (RF-10) — placeholder
                  Expanded(
                    flex: 5,
                    child: Container(
                      width: double.infinity,
                      color: SmartBusColors.verdePasajero.withValues(alpha: 0.08),
                      child: const Center(
                        child: Icon(
                          Icons.directions_bus_filled,
                          size: 56,
                          color: SmartBusColors.verdePasajero,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ETA (RF-11), computed by the AI microservice
                          Row(
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                color: SmartBusColors.verdePasajero,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Llega en 6 minutos',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Status / delay alert (RF-12)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCEFD9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFE0A03A),
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Sin incidencias reportadas en este recorrido',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Próximas paradas',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  ListTile(
                                    dense: true,
                                    leading: Icon(Icons.location_on_outlined),
                                    title: Text('Parada Central'),
                                    trailing: Text('2 min'),
                                  ),
                                  ListTile(
                                    dense: true,
                                    leading: Icon(Icons.location_on_outlined),
                                    title: Text('Universidad Nacional'),
                                    trailing: Text('6 min'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
