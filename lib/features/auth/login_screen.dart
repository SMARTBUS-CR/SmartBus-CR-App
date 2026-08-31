import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/login_form.dart';

/// Rol elegido en el selector temporal de vista previa (ver [_DevRoleToggle]
/// más abajo). Solo existe para poder navegar a la interfaz correcta
/// mientras no hay backend real devolviendo el rol.
enum _DevRole { passenger, driver }

/// Pantalla de login única para SmartBus Global.
///
/// Es completamente independiente del rol del usuario: el mismo formulario
/// se usa para pasajeros, conductores o cualquier otro rol futuro. El rol
/// lo determina el backend en la respuesta de autenticación; la navegación
/// a la interfaz correspondiente ocurre después del login, no aquí.
///
/// NOTA TEMPORAL: como todavía no hay backend conectado, se agregó un
/// selector de "vista previa" (Pasajero / Conductor) solo para poder ver
/// cómo queda cada flujo después de iniciar sesión. Bórralo junto con
/// [_DevRole] y [_DevRoleToggle] cuando `_handleLogin` navegue según el
/// rol real que devuelva la API.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _DevRole _devRole = _DevRole.passenger;

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> _handleLogin(
    BuildContext context,
    String email,
    String password,
  ) async {
    /*
     * AQUÍ SE CONECTARÁ CON TU API DE LARAVEL
     *
     * Ejemplo:
     *
     * POST /api/login
     *
     * {
     *   "email": "...",
     *   "password": "..."
     * }
     *
     * La API devolverá algo como:
     *
     * {
     *   "token": "...",
     *   "user": {
     *      "id": 1,
     *      "name": "...",
     *      "email": "...",
     *      "role": "passenger"
     *   }
     * }
     *
     * Cuando esté conectada, la navegación de abajo debe usar
     * user.role en vez de _devRole.
     */

    await Future.delayed(const Duration(seconds: 1));

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Inicio de sesión exitoso'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final destination =
        _devRole == _DevRole.driver ? '/driver/home' : '/passenger/home';
    Navigator.pushReplacementNamed(context, destination);
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
            // El blanco llena el resto de la pantalla (sin importar qué
            // tan corto sea el formulario), así no queda un hueco gris
            // debajo. Solo hace scroll si el contenido no cabe.
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildDevRoleToggle(),
                      LoginForm(
                        // Precargados solo para la vista previa temporal:
                        // así "Iniciar sesión" funciona sin tener que
                        // escribir nada. Bórralo junto con _DevRole.
                        initialEmail: 'demo@smartbus.cr',
                        initialPassword: 'demo1234',
                        onLogin: (email, password) =>
                            _handleLogin(context, email, password),
                      ),
                    ],
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
  // SELECTOR TEMPORAL DE ROL (borrar cuando haya backend real)
  // ============================================================

  Widget _buildDevRoleToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 18, 25, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VISTA PREVIA (TEMPORAL) · ENTRAR COMO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<_DevRole>(
            segments: const [
              ButtonSegment(
                value: _DevRole.passenger,
                label: Text('Pasajero'),
                icon: Icon(Icons.person_outline),
              ),
              ButtonSegment(
                value: _DevRole.driver,
                label: Text('Conductor'),
                icon: Icon(Icons.drive_eta_outlined),
              ),
            ],
            selected: {_devRole},
            onSelectionChanged: (selection) {
              setState(() => _devRole = selection.first);
            },
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: SmartBusColors.azulPrincipal,
              selectedForegroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(BuildContext context) {
    // Escala el texto superpuesto según el ancho real del celular.
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 390).clamp(0.85, 1.15);

    return Container(
      width: double.infinity,
      color: SmartBusColors.grisClaro,
      child: Stack(
        children: [
          Column(
            children: [
              // Ilustración oficial: logo, mapa, ruta y bus ya incluidos.
              AspectRatio(
                aspectRatio: 1553 / 1013,
                child: Image.asset(
                  'assets/images/inicio sesion.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),

              // Espacio extra debajo de la foto para que el texto
              // superpuesto tenga más aire.
              SizedBox(height: 46 * scale),
            ],
          ),

          // Texto superpuesto sobre la foto (y el espacio extra).
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
