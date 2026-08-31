import 'package:flutter/material.dart';

/// Isotipo + wordmark de SmartBus Global.
///
/// Usa el logo oficial (`assets/images/logo SMARTBUS.png`, ya incluye el
/// pin con el bus, "SMARTBUS GLOBAL" y el eslogan). Reutilizable en
/// cualquier pantalla que necesite mostrar la marca (login, splash,
/// onboarding, etc.).
class SmartBusLogo extends StatelessWidget {
  const SmartBusLogo({super.key, this.width = 150});

  /// Ancho del logo. La imagen es cuadrada, así que el alto es igual.
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
