import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Formulario de login de SmartBus Global.
///
/// No conoce el rol del usuario: solo captura credenciales y delega la
/// autenticación al callback [onLogin]. Qué hacer tras un login exitoso
/// (mensaje, navegación por rol, etc.) es responsabilidad de quien use
/// este formulario, no de él.
class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.onLogin,
    this.onForgotPassword,
    this.onRegisterPassenger,
    this.initialEmail,
    this.initialPassword,
  });

  /// Se invoca con (email, password) ya validados como no vacíos.
  final Future<void> Function(String email, String password) onLogin;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onRegisterPassenger;

  /// Precargan los campos (p. ej. credenciales de prueba mientras no hay
  /// backend real). Se pueden editar o borrar normalmente.
  final String? initialEmail;
  final String? initialPassword;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  late final emailController =
      TextEditingController(text: widget.initialEmail);
  late final passwordController =
      TextEditingController(text: widget.initialPassword);

  bool obscurePassword = true;
  bool rememberMe = false;
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Completa todos los campos');
      return;
    }

    setState(() => isLoading = true);
    try {
      await widget.onLogin(email, password);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Escala los tamaños según el ancho real del celular (referencia 390px),
    // acotada para no verse ni diminuta en pantallas chicas ni gigante en
    // pantallas grandes.
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 390).clamp(0.85, 1.15);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(25 * scale, 25 * scale, 25 * scale, 27 * scale),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Email
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDecoration(
              icon: Icons.person_outline,
              hint: 'Correo electrónico',
              scale: scale,
            ),
          ),

          SizedBox(height: 20 * scale),

          // Password
          TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            decoration: _inputDecoration(
              icon: Icons.lock_outline,
              hint: 'Contraseña',
              scale: scale,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => obscurePassword = !obscurePassword);
                },
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.grey.shade600,
                  size: 20 * scale,
                ),
              ),
            ),
          ),

          SizedBox(height: 15 * scale),

          // Recordarme
          Row(
            children: [
              SizedBox(
                width: 20 * scale,
                height: 20 * scale,
                child: Checkbox(
                  value: rememberMe,
                  activeColor: SmartBusColors.azulPrincipal,
                  onChanged: (value) {
                    setState(() => rememberMe = value ?? false);
                  },
                ),
              ),

              SizedBox(width: 5 * scale),

              Text(
                'Recordarme',
                style: TextStyle(
                  color: SmartBusColors.azulCorporativo,
                  fontSize: 12 * scale,
                ),
              ),

              const Spacer(),

              GestureDetector(
                onTap: widget.onForgotPassword ??
                    () => _showMessage('Recuperación de contraseña'),
                child: Text(
                  '¿Olvidaste tu contraseña?',
                  style: TextStyle(
                    color: SmartBusColors.azulPrincipal,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 28 * scale),

          // Botón
          _buildLoginButton(scale),

          SizedBox(height: 18 * scale),

          // Registro
          Center(
            child: GestureDetector(
              onTap: widget.onRegisterPassenger ??
                  () => _showMessage('Registro de pasajero'),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13 * scale,
                    color: Colors.grey.shade600,
                  ),
                  children: [
                    const TextSpan(text: '¿No tienes cuenta? '),
                    TextSpan(
                      text: 'Regístrate como pasajero',
                      style: TextStyle(
                        color: SmartBusColors.azulPrincipal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required IconData icon,
    required String hint,
    required double scale,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13 * scale),
      prefixIcon: Icon(icon, color: Colors.grey.shade600, size: 20 * scale),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFFAFBFD),
      contentPadding: EdgeInsets.symmetric(
        vertical: 15 * scale,
        horizontal: 12 * scale,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: SmartBusColors.azulPrincipal,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildLoginButton(double scale) {
    return SizedBox(
      width: double.infinity,
      height: 48 * scale,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              SmartBusColors.azulPrincipal,
              SmartBusColors.verdeTurquesa,
            ],
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: isLoading
              ? SizedBox(
                  width: 22 * scale,
                  height: 22 * scale,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.login, color: Colors.white, size: 21 * scale),
                    SizedBox(width: 12 * scale),
                    Text(
                      'Iniciar sesión',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
