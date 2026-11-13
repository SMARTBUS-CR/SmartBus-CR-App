import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../../widgets/account_form.dart';
import '../../widgets/smartbus_header.dart';
import '../auth/models/auth_user.dart';
import '../auth/services/auth_service.dart';
import '../auth/verify_email_screen.dart';

/// Passenger "Editar perfil": name and email.
///
/// Only the fields that changed are sent (`PATCH /auth/user`). Changing the
/// email asks for the current password and, once saved, the new address must
/// be verified again with a 6-digit code: the screen goes to `/verify-email`,
/// which signs the user back in. Pops with the updated [AuthUser] when only
/// the name changed.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.user,
    this.authService,
    this.sessionStore,
  });

  /// Current profile, used to pre-fill the form and detect changes.
  final AuthUser user;

  /// Injectable for tests; defaults to a real [AuthService].
  final AuthService? authService;

  /// Injectable for tests; defaults to a real [SecureSessionStore].
  final SecureSessionStore? sessionStore;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final SecureSessionStore _session =
      widget.sessionStore ?? SecureSessionStore();
  late final AuthService _authService =
      widget.authService ?? AuthService(sessionStore: _session);

  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.user.name);
  late final _emailController = TextEditingController(text: widget.user.email);
  final _currentPasswordController = TextEditingController();

  bool _obscureCurrentPassword = true;
  bool _isLoading = false;

  /// Backend validation errors (422) per field: `name`, `email`,
  /// `current_password`. A field's entry is cleared as soon as it is edited.
  Map<String, List<String>> _serverErrors = const {};

  // Same limits as the Auth service `UpdatePassengerProfileRequest`.
  static const _maxLength = 100;
  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    super.dispose();
  }

  String get _newName => _nameController.text.trim();
  String get _newEmail => _emailController.text.trim();

  bool get _nameChanged => _newName != widget.user.name;

  /// Case-insensitive: changing only the case is not a new address and would
  /// needlessly force a new verification.
  bool get _emailChanged =>
      _newEmail.toLowerCase() != widget.user.email.toLowerCase();

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

  String? _validateCurrentPassword(String? value) {
    if (!_emailChanged) return null;
    if ((value ?? '').isEmpty) {
      return 'Ingresa tu contraseña actual para cambiar el correo';
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

    // Nothing changed: no request, back to the profile.
    if (!_nameChanged && !_emailChanged) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _authService.updateProfile(
        name: _nameChanged ? _newName : null,
        email: _emailChanged ? _newEmail : null,
        currentPassword: _emailChanged ? _currentPasswordController.text : null,
      );
      if (!mounted) return;

      if (result.requiresEmailVerification) {
        // The session was closed: the new address must be verified with a
        // code (requested as the screen opens), which signs the user in
        // again. Nothing to go back to.
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/verify-email',
          (_) => false,
          arguments: VerifyEmailArgs(email: _newEmail, resendOnOpen: true),
        );
        return;
      }

      _showMessage(
        'Perfil actualizado correctamente.',
        color: SmartBusColors.completado,
      );
      Navigator.pop(context, result.user);
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

  static const _formFields = {'name', 'email', 'current_password'};

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
            title: 'Editar perfil',
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
          key: const Key('edit_profile_name'),
          controller: _nameController,
          enabled: !_isLoading,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: _validateName,
          onChanged: (_) => _clearServerError('name'),
          decoration: accountInputDecoration(
            icon: Icons.badge_outlined,
            label: 'Nombre completo',
            serverError: _serverError('name'),
          ),
        ),
        const SizedBox(height: 18),
        TextFormField(
          key: const Key('edit_profile_email'),
          controller: _emailController,
          enabled: !_isLoading,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          validator: _validateEmail,
          onChanged: (_) {
            _clearServerError('email');
            // Shows / hides "Contraseña actual".
            setState(() {});
          },
          decoration: accountInputDecoration(
            icon: Icons.email_outlined,
            label: 'Correo electrónico',
            serverError: _serverError('email'),
          ),
        ),
        // Only needed (and only shown) when the email changes.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _emailChanged
              ? _buildEmailChangeFields()
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 28),
        AccountSubmitButton(
          key: const Key('edit_profile_save'),
          label: 'Guardar',
          isLoading: _isLoading,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _buildEmailChangeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCurrentPasswordField(),
        const SizedBox(height: 10),
        Row(
          key: const Key('edit_profile_email_notice'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Al cambiar tu correo te enviaremos un código para '
                'verificarlo y deberás ingresarlo para volver a entrar.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCurrentPasswordField() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: TextFormField(
        key: const Key('edit_profile_current_password'),
        controller: _currentPasswordController,
        enabled: !_isLoading,
        obscureText: _obscureCurrentPassword,
        textInputAction: TextInputAction.done,
        validator: _validateCurrentPassword,
        onChanged: (_) => _clearServerError('current_password'),
        onFieldSubmitted: (_) => _save(),
        decoration: accountInputDecoration(
          icon: Icons.lock_outline,
          label: 'Contraseña actual',
          serverError: _serverError('current_password'),
          suffixIcon: PasswordVisibilityToggle(
            obscured: _obscureCurrentPassword,
            onPressed: () => setState(
              () => _obscureCurrentPassword = !_obscureCurrentPassword,
            ),
          ),
        ),
      ),
    );
  }
}
