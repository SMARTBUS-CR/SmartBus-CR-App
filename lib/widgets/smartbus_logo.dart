import 'package:flutter/material.dart';

/// SmartBus Global icon + wordmark.
///
/// Uses the official logo (`assets/images/logo SMARTBUS.png`, which already
/// includes the bus pin, "SMARTBUS GLOBAL" and the slogan). Reusable on any
/// screen that needs to show the brand (login, splash, onboarding, etc.).
class SmartBusLogo extends StatelessWidget {
  const SmartBusLogo({super.key, this.width = 150});

  /// Logo width. The image is square, so the height matches.
  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo SMARTBUS.png',
      width: width,
      fit: BoxFit.contain,
      semanticLabel: 'SmartBus Global',
    );
  }
}
