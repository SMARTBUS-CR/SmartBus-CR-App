import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../../widgets/account_form.dart';
import '../../widgets/password_requirements.dart';
import '../../widgets/smartbus_header.dart';
import '../auth/services/auth_service.dart';

/// Passenger "Cambiar contraseña": current password + new password +
/// confirmation (`PUT /auth/user/password`).
///
/// The user stays signed in on this device; the backend closes the sessions
/// on other devices. Pops back to the profile on success.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.authService, this.sessionStore});

  /// Injectable for tests; defaults to a real [AuthService].
  final AuthService? authService;

  /// Injectable for tests; defaults to a real [SecureSessionStore].
  final SecureSessionStore? sessionStore;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  late final SecureSessionStore _session =
      widget.sessionStore ?? SecureSessionStore();
  late final AuthService _authService =
      widget.authService ?? AuthService(sessionStore: _session);

  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  /// Lets the new password re-validate the confirmation while typing.
  final _confirmFieldKey = GlobalKey<FormFieldState<String>>();

  bool _obscureCurrent = true;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  /// Backend validation errors (422) per field: `current_password`,
  /// `password`. A field's entry is cleared as soon as it is edited.
  Map<String, List<String>> _serverErrors = const {};

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ============================================================
  // VALIDATION (client side)
  // ============================================================

  String? _validateCurrent(String? value) {
    if ((value ?? '').isEmpty) return 'Ingresa tu contraseña actual';
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Ingresa la nueva contraseña';
    // Which rules are missing is shown by the checklist below the field.
    if (PasswordRule.missing(password).isNotEmpty) {
      return 'La contraseña no es segura';
    }
    if (password == _currentController.text) {
      return 'La nueva contraseña debe ser distinta de la actual';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if ((value ?? '').isEmpty) return 'Confirma la nueva contraseña';
    if (value != _passwordController.text) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  // ============================================================
  // SUBMIT
  // ============================================================

  Future<void> _save() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();
    setState(() => _serverErrors = const {});
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final message = await _authService.changePassword(
        currentPassword: _currentController.text,
        password: _passwordController.text,
        passwordConfirmation: _confirmController.text,
      );
      if (!mounted) return;
      _showMessage(message, color: SmartBusColors.completado);
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.type) {
        case ApiErrorType.validation when e.fieldErrors.isNotEmpty:
          setState(() => _serverErrors = e.fieldErrors);
          if (!_hasVisibleFieldError(e.fieldErrors)) {
            _showMessage(e.message, color: SmartBusColors.error);
          }
        case ApiErrorType.unauthorized:
          await _onSessionExpired(e.message);
        default:
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

  Future<void> _onSessionExpired(String message) async {
    await _session.clear();
    if (!mounted) return;
    _showMessage(message, color: SmartBusColors.error);
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  /// `password_confirmation` errors come back under `password` (Laravel's
  /// `confirmed` rule), so only these two fields are shown.
  static const _formFields = {'current_password', 'password'};

  bool _hasVisibleFieldError(Map<String, List<String>> errors) =>
      errors.keys.any(_formFields.contains);

  String? _serverError(String field) {
    final messages = _serverErrors[field];
    return messages == null || messages.isEmpty ? null : messages.join('\n');
  }

  void _clearServerError(String field) {
    if (!_serverErrors.containsKey(field)) return;
    setState(() => _serverErrors = Map.of(_serverErrors)..remove(field));
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
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      body: Column(
        children: [
          SmartBusHeader(
            title: 'Cambiar contraseña',
            type: SmartBusUserType.passenger,
            onBack: _isLoading ? null : () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Form(key: _formKey, child: _buildFields()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('change_password_current'),
          controller: _currentController,
          enabled: !_isLoading,
          obscureText: _obscureCurrent,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.password],
          validator: _validateCurrent,
          onChanged: (_) => _clearServerError('current_password'),
          decoration: accountInputDecoration(
            icon: Icons.lock_outline,
            label: 'Contraseña actual',
            serverError: _serverError('current_password'),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _obscureCurrent,
              onPressed: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
            ),
          ),
        ),
        const SizedBox(height: 18),
        TextFormField(
          key: const Key('change_password_new'),
          controller: _passwordController,
          enabled: !_isLoading,
          obscureText: _obscurePassword,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          validator: _validatePassword,
          onChanged: (_) {
            _clearServerError('password');
            // Keep "Las contraseñas no coinciden" in sync.
            if (_confirmController.text.isNotEmpty) {
              _confirmFieldKey.currentState?.validate();
            }
          },
          decoration: accountInputDecoration(
            icon: Icons.lock_reset_outlined,
            label: 'Nueva contraseña',
            serverError: _serverError('password'),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _obscurePassword,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        PasswordRequirements(controller: _passwordController),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: const Key('change_password_confirm'),
          child: TextFormField(
            key: _confirmFieldKey,
            controller: _confirmController,
            enabled: !_isLoading,
            obscureText: _obscureConfirm,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            textInputAction: TextInputAction.done,
            validator: _validateConfirm,
            onFieldSubmitted: (_) => _save(),
            decoration: accountInputDecoration(
              icon: Icons.lock_reset_outlined,
              label: 'Confirmar nueva contraseña',
              suffixIcon: PasswordVisibilityToggle(
                obscured: _obscureConfirm,
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        AccountSubmitButton(
          key: const Key('change_password_save'),
          label: 'Guardar',
          isLoading: _isLoading,
          onPressed: _save,
        ),
      ],
    );
  }
}
