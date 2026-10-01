import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import 'role_home.dart';
import 'services/auth_service.dart';

/// Passenger sign-up screen.
///
/// Only **passengers** can create an account from the app (drivers are created
/// in the admin panel), so there is no role selector: the backend assigns the
/// `passenger` role and returns a session, which means a successful sign-up
/// goes straight to the passenger home (auto-login).
///
/// The client-side rules mirror the Auth service `RegisterRequest`, so most
/// mistakes are caught before the request. Anything the app cannot check
/// (email already registered, compromised password) comes back as a 422 and is
/// shown under the matching field.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.authService});

  /// Injectable for tests; defaults to a real [AuthService].
  final AuthService? authService;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  /// After the first submit, fields re-validate while the user types.
  bool _submitted = false;

  /// Backend validation errors (422) per field: `name`, `email`, `password`.
  /// A field's entry is cleared as soon as the user edits it.
  Map<String, List<String>> _serverErrors = const {};

  // Same limits as the Auth service `RegisterRequest`.
  static const _maxLength = 100;
  static const _minPasswordLength = 8;
  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ============================================================
  // VALIDATION (client side)
  // ============================================================

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Ingresa tu nombre';
    if (name.length > _maxLength) {
      return 'El nombre no puede superar $_maxLength caracteres';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Ingresa tu correo electrónico';
    if (email.length > _maxLength) {
      return 'El correo no puede superar $_maxLength caracteres';
    }
    if (!_emailRegExp.hasMatch(email)) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Ingresa una contraseña';

    final missing = <String>[
      if (password.length < _minPasswordLength)
        'al menos $_minPasswordLength caracteres',
      if (!password.contains(RegExp(r'[A-Z]'))) 'una mayúscula',
      if (!password.contains(RegExp(r'[a-z]'))) 'una minúscula',
      if (!password.contains(RegExp(r'[0-9]'))) 'un número',
      if (!password.contains(RegExp(r'[^A-Za-z0-9]'))) 'un símbolo',
    ];
    if (missing.isEmpty) return null;
    return 'La contraseña debe tener ${_joinSpanish(missing)}';
  }

  String? _validateConfirm(String? value) {
    if ((value ?? '').isEmpty) return 'Confirma tu contraseña';
    if (value != _passwordController.text) return 'Las contraseñas no coinciden';
    return null;
  }

  /// "a", "a y b", "a, b y c".
  static String _joinSpanish(List<String> items) {
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }

  // ============================================================
  // SUBMIT
  // ============================================================

  Future<void> _submit() async {
    // Prevent firing two requests at once.
    if (_isLoading) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
      _serverErrors = const {};
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final session = await _authService.registerPassenger(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        passwordConfirmation: _confirmController.text,
      );

      if (!mounted) return;
      _showMessage(
        '¡Cuenta creada! Bienvenido(a) a SmartBus.',
        color: SmartBusColors.completado,
      );
      // Auto-login: the sign-up response already carries the session. The
      // stack is cleared so "back" does not return to the sign-up / login.
      Navigator.pushNamedAndRemoveUntil(
        context,
        homeRouteForUser(session.user) ?? '/passenger/home',
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.type == ApiErrorType.validation && e.fieldErrors.isNotEmpty) {
        setState(() => _serverErrors = e.fieldErrors);
        // Show it under the fields; the SnackBar is only for errors that do
        // not belong to any visible field.
        if (!_hasVisibleFieldError(e.fieldErrors)) {
          _showMessage(e.message, color: SmartBusColors.error);
        }
      } else {
        _showMessage(e.message, color: SmartBusColors.error);
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Ocurrió un error inesperado. Inténtalo nuevamente.',
        color: SmartBusColors.error,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _formFields = {'name', 'email', 'password'};

  bool _hasVisibleFieldError(Map<String, List<String>> errors) =>
      errors.keys.any(_formFields.contains);

  /// First backend message for [field], or `null`.
  String? _serverError(String field) {
    final messages = _serverErrors[field];
    return messages == null || messages.isEmpty ? null : messages.join('\n');
  }

  void _clearServerError(String field) {
    if (!_serverErrors.containsKey(field)) return;
    setState(() {
      _serverErrors = Map.of(_serverErrors)..remove(field);
    });
  }

  void _showMessage(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 390).clamp(0.85, 1.15);

    return Scaffold(
      backgroundColor: SmartBusColors.grisClaro,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(scale),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    25 * scale,
                    25 * scale,
                    25 * scale,
                    27 * scale,
                  ),
                  child: _buildForm(scale),
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

  Widget _buildHeader(double scale) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8 * scale, 8 * scale, 27 * scale, 20 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: _isLoading ? null : () => Navigator.maybePop(context),
            icon: const Icon(
              Icons.arrow_back,
              color: SmartBusColors.azulCorporativo,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: 19 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Crear cuenta',
                      style: TextStyle(
                        color: SmartBusColors.azulCorporativo,
                        fontSize: 22 * scale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 7 * scale),
                    Icon(
                      Icons.person_add_alt_1,
                      color: SmartBusColors.verdeTurquesa,
                      size: 24 * scale,
                    ),
                  ],
                ),
                SizedBox(height: 5 * scale),
                Text(
                  'Regístrate como pasajero para usar SmartBus',
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

  // ============================================================
  // FORM
  // ============================================================

  Widget _buildForm(double scale) {
    return Form(
      key: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: AutofillGroup(
        child: Column(
          children: [
            // Name
            TextFormField(
              key: const Key('register_name'),
              controller: _nameController,
              enabled: !_isLoading,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              validator: _validateName,
              onChanged: (_) => _clearServerError('name'),
              decoration: _inputDecoration(
                icon: Icons.badge_outlined,
                hint: 'Nombre completo',
                scale: scale,
                serverError: _serverError('name'),
              ),
            ),

            SizedBox(height: 18 * scale),

            // Email
            TextFormField(
              key: const Key('register_email'),
              controller: _emailController,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              validator: _validateEmail,
              onChanged: (_) => _clearServerError('email'),
              decoration: _inputDecoration(
                icon: Icons.person_outline,
                hint: 'Correo electrónico',
                scale: scale,
                serverError: _serverError('email'),
              ),
            ),

            SizedBox(height: 18 * scale),

            // Password
            TextFormField(
              key: const Key('register_password'),
              controller: _passwordController,
              enabled: !_isLoading,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              validator: _validatePassword,
              onChanged: (_) => _clearServerError('password'),
              decoration: _inputDecoration(
                icon: Icons.lock_outline,
                hint: 'Contraseña',
                scale: scale,
                helper:
                    'Mínimo 8 caracteres, con mayúscula, minúscula, número y símbolo.',
                serverError: _serverError('password'),
                suffixIcon: _visibilityToggle(
                  obscured: _obscurePassword,
                  scale: scale,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),

            SizedBox(height: 18 * scale),

            // Confirm password
            TextFormField(
              key: const Key('register_password_confirmation'),
              controller: _confirmController,
              enabled: !_isLoading,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              validator: _validateConfirm,
              onFieldSubmitted: (_) => _submit(),
              decoration: _inputDecoration(
                icon: Icons.lock_reset_outlined,
                hint: 'Confirmar contraseña',
                scale: scale,
                suffixIcon: _visibilityToggle(
                  obscured: _obscureConfirm,
                  scale: scale,
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),

            SizedBox(height: 28 * scale),

            _buildSubmitButton(scale),

            SizedBox(height: 18 * scale),

            // Back to login
            Center(
              child: GestureDetector(
                onTap: _isLoading ? null : () => Navigator.maybePop(context),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 13 * scale,
                      color: Colors.grey.shade600,
                    ),
                    children: const [
                      TextSpan(text: '¿Ya tienes cuenta? '),
                      TextSpan(
                        text: 'Inicia sesión',
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

  Widget _visibilityToggle({
    required bool obscured,
    required double scale,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: obscured ? 'Mostrar contraseña' : 'Ocultar contraseña',
      onPressed: onPressed,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: Colors.grey.shade600,
        size: 20 * scale,
      ),
    );
  }

  /// Same look as the login inputs ([LoginForm]).
  InputDecoration _inputDecoration({
    required IconData icon,
    required String hint,
    required double scale,
    String? helper,
    String? serverError,
    Widget? suffixIcon,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13 * scale),
      prefixIcon: Icon(icon, color: Colors.grey.shade600, size: 20 * scale),
      suffixIcon: suffixIcon,
      helperText: helper,
      helperMaxLines: 2,
      helperStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11 * scale),
      // Backend (422) errors; client-side ones come from the validator.
      errorText: serverError,
      errorMaxLines: 4,
      filled: true,
      fillColor: const Color(0xFFFAFBFD),
      contentPadding: EdgeInsets.symmetric(
        vertical: 15 * scale,
        horizontal: 12 * scale,
      ),
      border: border(Colors.grey.shade200),
      enabledBorder: border(Colors.grey.shade200),
      disabledBorder: border(Colors.grey.shade200),
      focusedBorder: border(SmartBusColors.azulPrincipal, 1.5),
      errorBorder: border(SmartBusColors.error),
      focusedErrorBorder: border(SmartBusColors.error, 1.5),
    );
  }

  Widget _buildSubmitButton(double scale) {
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
          key: const Key('register_submit'),
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: _isLoading
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
                    Icon(
                      Icons.how_to_reg,
                      color: Colors.white,
                      size: 21 * scale,
                    ),
                    SizedBox(width: 12 * scale),
                    Text(
                      'Crear cuenta',
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
