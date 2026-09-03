import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'role_home.dart';
import 'services/auth_service.dart';

/// Startup splash: shown right after the native splash (white background + logo)
/// while the app decides where to go.
///
/// - If there is a stored session and the token is still valid
///   (`GET /auth/user` through the Gateway) → go straight to the screen for the
///   matching role.
/// - If there is no session, or the token is invalid/expired → go to login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _minSplash = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final startedAt = DateTime.now();

    String nextRoute;
    try {
      final user = await AuthService().restoreSession();
      if (user == null) {
        nextRoute = '/login';
      } else {
        // Valid session but the role has no dedicated screen yet → go to login.
        nextRoute = homeRouteForUser(user) ?? '/login';
      }
    } catch (_) {
      nextRoute = '/login';
    }

    // Avoid a splash "flash" when the check finishes very quickly.
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < _minSplash) {
      await Future.delayed(_minSplash - elapsed);
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, nextRoute);
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
