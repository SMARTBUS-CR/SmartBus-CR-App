import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'slow_request_hint.dart';

/// SmartBus Global login form.
///
/// It does not know the user's role: it only captures credentials and delegates
/// authentication to the [onLogin] callback. What to do after a successful login
/// (message, role-based navigation, etc.) is the responsibility of whoever uses
/// this form, not the form itself.
class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.onLogin,
    this.onForgotPassword,
    this.onRegisterPassenger,
    this.initialEmail,
    this.initialPassword,
  });

  /// Called with (email, password) already validated as non-empty.
  final Future<void> Function(String email, String password) onLogin;

  /// "¿Olvidaste tu contraseña?", with the email typed so far (trimmed).
  final ValueChanged<String>? onForgotPassword;
  final VoidCallback? onRegisterPassenger;

  /// Pre-fill the fields (e.g. test credentials). Can be edited or cleared
  /// normally.
  final String? initialEmail;
  final String? initialPassword;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  late final emailController = TextEditingController(text: widget.initialEmail);
  late final passwordController = TextEditingController(
    text: widget.initialPassword,
  );

  bool obscurePassword = true;
  bool rememberMe = false;
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  final _formKey = GlobalKey<FormState>();

  // Basic email shape: something@something.domain (no spaces).
  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Ingresa tu correo electrónico';
    if (!_emailRegExp.hasMatch(email)) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  /// Only "not empty": password strength is NOT checked at login, because
  /// existing accounts may have older passwords that do not meet the
  /// sign-up rules. Wrong passwords are reported by the backend.
  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return 'Ingresa tu contraseña';
    return null;
  }

  Future<void> _submit() async {
    // Prevent firing two requests at once.
    if (isLoading) return;

    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final email = emailController.text.trim();
    final password = passwordController.text;

    setState(() => isLoading = true);
    try {
      await widget.onLogin(email, password);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _forgotPassword() {
    final onForgot = widget.onForgotPassword;
    if (onForgot == null) {
      _showMessage('Recuperación de contraseña');
      return;
    }
    onForgot(emailController.text.trim());
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Scale sizes to the real device width (390px reference), clamped so it
    // does not look tiny on small screens or huge on large ones.
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 390).clamp(0.85, 1.15);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        25 * scale,
        25 * scale,
        25 * scale,
        27 * scale,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Email
            TextFormField(
              // Real-time: validates this field as soon as the user types in it.
              autovalidateMode: AutovalidateMode.onUserInteraction,
              key: const Key('login_email'),
              controller: emailController,
              enabled: !isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              validator: _validateEmail,
              decoration: _inputDecoration(
                icon: Icons.person_outline,
                hint: 'Correo electrónico',
                scale: scale,
              ),
            ),

            SizedBox(height: 20 * scale),

            // Password
            TextFormField(
              // Real-time: validates this field as soon as the user types in it.
              autovalidateMode: AutovalidateMode.onUserInteraction,
              key: const Key('login_password'),
              controller: passwordController,
              enabled: !isLoading,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              validator: _validatePassword,
              onFieldSubmitted: (_) => _submit(),
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

            // Remember me
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

                SizedBox(width: 12 * scale),

                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      key: const Key('login_forgot_password'),
                      onTap: isLoading ? null : _forgotPassword,
                      child: Text(
                        '¿Olvidaste tu contraseña?',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: SmartBusColors.azulPrincipal,
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 28 * scale),

            // Button
            _buildLoginButton(scale),

            if (isLoading) const SlowRequestHint(),

            SizedBox(height: 18 * scale),

            // Sign up
            Center(
              child: GestureDetector(
                onTap:
                    widget.onRegisterPassenger ??
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
