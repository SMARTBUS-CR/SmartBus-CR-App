import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/login_form.dart';
import 'role_home.dart';
import 'services/auth_service.dart';

/// Single login screen for SmartBus Global.
///
/// It is completely role-agnostic: the same form is used for passengers,
/// drivers or any future role. The role is decided by the backend in the
/// authentication response; navigation to the matching interface happens after
/// login, not here.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> _handleLogin(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final session = await _authService.login(
        email: email,
        password: password,
      );

      if (!context.mounted) return;

      final route = homeRouteForUser(session.user);
      if (route == null) {
        // Valid login but the role has no interface in the app yet (e.g. admin).
        await _authService.logout();
        if (!context.mounted) return;
        _showError(
          context,
          'Tu tipo de cuenta aún no tiene una vista disponible en la app.',
        );
        return;
      }

      Navigator.pushReplacementNamed(context, route);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      _showError(context, e.message);
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, 'Ocurrió un error inesperado. Inténtalo nuevamente.');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: SmartBusColors.error,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartBusColors.grisClaro,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            // The white area fills the rest of the screen (no matter how short
            // the form is) so there is no grey gap below it. It only scrolls
            // if the content does not fit.
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: LoginForm(
                    onLogin: (email, password) =>
                        _handleLogin(context, email, password),
                    onRegisterPassenger: () =>
                        Navigator.pushNamed(context, '/register'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(BuildContext context) {
    // Scales the overlaid text to the real device width.
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 390).clamp(0.85, 1.15);

    return Container(
      width: double.infinity,
      color: SmartBusColors.grisClaro,
      child: Stack(
        children: [
          Column(
            children: [
              // Official illustration: logo, map, route and bus already included.
              AspectRatio(
                aspectRatio: 1553 / 1013,
                child: Image.asset(
                  'assets/images/inicio sesion.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),

              // Extra space below the image so the overlaid text has more room.
              SizedBox(height: 46 * scale),
            ],
          ),

          // Text overlaid on the image (and the extra space).
          Positioned(
            left: 27 * scale,
            bottom: 20 * scale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Bienvenido',
                      style: TextStyle(
                        color: SmartBusColors.azulCorporativo,
                        fontSize: 22 * scale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 7 * scale),
                    Icon(
                      Icons.person,
                      color: SmartBusColors.verdeTurquesa,
                      size: 24 * scale,
                    ),
                  ],
                ),

                SizedBox(height: 5 * scale),

                Text(
                  'Inicia sesión para continuar',
                  style: TextStyle(
                    color: SmartBusColors.azulCorporativo,
                    fontSize: 13 * scale,
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
