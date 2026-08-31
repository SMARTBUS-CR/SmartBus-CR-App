import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Splash de arranque: se muestra justo después del splash nativo
/// (fondo blanco + logo) para dar tiempo a que la app inicialice,
/// con una barra de carga del mismo color que el botón de login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icons/icon_circle.png',
              width: 180,
              height: 180,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  minHeight: 4,
                  color: SmartBusColors.azulPrincipal,
                  backgroundColor: Color(0xFFE0E0E0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
