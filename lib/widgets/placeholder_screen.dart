import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Pantalla base para las vistas aún sin funcionalidad real: header de
/// color con título, flecha de regreso opcional y un aviso de
/// "Próximamente" sobre el fondo blanco solapado.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.color,
    this.bottomNavigationBar,
    this.onBack,
    this.footer,
  });

  final String title;
  final IconData icon;
  final String subtitle;
  final Color color;
  final Widget? bottomNavigationBar;
  final VoidCallback? onBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        elevation: 0,
        toolbarHeight: 40,
        automaticallyImplyLeading: false,
        leading: onBack == null
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: SmartBusColors.blanco,
                ),
                onPressed: onBack,
              ),
      ),
      bottomNavigationBar: bottomNavigationBar,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 70),
            alignment: Alignment.center,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 64, color: Colors.black26),
                        const SizedBox(height: 12),
                        const Text(
                          'Próximamente',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        if (footer != null) ...[const Spacer(), footer!],
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
