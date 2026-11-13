import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'smartbus_header.dart';

/// Base screen for views without real functionality yet: the branded
/// [SmartBusHeader] (with an optional back button) and a "Coming soon" notice
/// on the white content area.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.type,
    this.bottomNavigationBar,
    this.onBack,
    this.footer,
  });

  final String title;
  final IconData icon;
  final String subtitle;

  /// Role of the flow: sets the header gradient and illustration.
  final SmartBusUserType type;
  final Widget? bottomNavigationBar;
  final VoidCallback? onBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      bottomNavigationBar: bottomNavigationBar,
      body: Column(
        children: [
          SmartBusHeader(title: title, type: type, onBack: onBack),
          Expanded(
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
        ],
      ),
    );
  }
}
