import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/password_requirements.dart';
import '../../widgets/slow_request_hint.dart';
import 'services/auth_service.dart';

/// What `/forgot-password` returns to the login screen when the password was
/// changed: the email (to prefill it) and the backend message.
class PasswordResetDone {
  const PasswordResetDone({required this.email, required this.message});

  final String email;
  final String message;
}

/// "¿Olvidaste tu contraseña?" (`/forgot-password`), in two steps:
///
/// 1. **Email** → `POST /auth/password/forgot`: the Auth service emails a
///    6-digit code (valid for 15 minutes).
/// 2. **Code + new password** → `POST /auth/password/reset`. The new password
///    has the sign-up rules ([PasswordRequirements]). "Reenviar código" waits
///    [resendCooldown] seconds between requests.
///
/// On success it pops with a [PasswordResetDone], so the login screen shows
/// the message and prefills the email. The backend signs the account out on
/// every device. No token is used: the user is not signed in.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail, this.authService});

  /// What the user typed on the login screen (used only if it looks valid).
  final String? initialEmail;

  /// Injectable for tests; defaults to a real [AuthService].
  final AuthService? authService;

  /// Seconds before "Reenviar código" can be used again.
  static const resendCooldown = 60;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();

  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _confirmFieldKey = GlobalKey<FormFieldState<String>>();

  late final _emailController = TextEditingController(
    text: _looksLikeEmail(widget.initialEmail) ? widget.initialEmail : null,
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  /// `false` = step 1 (email), `true` = step 2 (code + new password).
  bool _codeSent = false;

  /// The email the code was sent to (fixed in step 2).
  String _email = '';

  bool _sending = false; // forgot (send / resend)
  bool _resetting = false; // reset
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// Backend errors under each field (`email`, `code`, `password`).
  Map<String, String> _serverErrors = const {};

  Timer? _cooldownTimer;
  int _cooldownLeft = 0;

  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _sixDigits = RegExp(r'^\d{6}$');

  static bool _looksLikeEmail(String? value) =>
      value != null && _emailRegExp.hasMatch(value.trim());

  bool get _busy => _sending || _resetting;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ============================================================
  // VALIDATION (client side)
  // ============================================================

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Ingresa tu correo electrónico';
    if (!_emailRegExp.hasMatch(email)) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  String? _validateCode(String? value) {
    // A wrong / expired code clears the field: the backend message must win
    // over "Ingresa el código…" until the user types again.
    if (_serverErrors['code'] case final error?) return error;
    final code = (value ?? '').trim();
    if (code.isEmpty) return 'Ingresa el código que te enviamos';
    if (!_sixDigits.hasMatch(code)) return 'El código tiene 6 dígitos';
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Ingresa la nueva contraseña';
    // Which rules are missing is shown by the checklist below the field.
    if (PasswordRule.missing(password).isNotEmpty) {
      return 'La contraseña no es segura';
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
  // ACTIONS
  // ============================================================

  /// Step 1 "Enviar código" (and step 2 "Reenviar código").
  Future<void> _sendCode() async {
    if (_busy) return;
    final resending = _codeSent;
    if (resending) {
      if (_cooldownLeft > 0) return;
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _serverErrors = const {});
      if (!_emailFormKey.currentState!.validate()) return;
    }
    final email = resending ? _email : _emailController.text.trim();

    setState(() => _sending = true);
    try {
      final message = await _authService.sendResetCode(email);
      if (!mounted) return;
      setState(() {
        _email = email;
        _codeSent = true;
        _serverErrors = const {};
      });
      _codeController.clear();
      _startCooldown();
      _showMessage(message, color: SmartBusColors.completado);
    } on ApiException catch (e) {
      if (!mounted) return;
      final emailError = e.fieldErrors['email'];
      if (e.type == ApiErrorType.validation &&
          emailError != null &&
          !resending) {
        // Unknown or invalid email: under the field.
        setState(() => _serverErrors = {'email': emailError.join('\n')});
      } else {
        _showError(e, onRetry: _sendCode);
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Ocurrió un error inesperado. Inténtalo nuevamente.',
        color: SmartBusColors.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Step 2 "Cambiar contraseña".
  Future<void> _reset() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _serverErrors = const {});
    if (!_resetFormKey.currentState!.validate()) return;

    setState(() => _resetting = true);
    try {
      final message = await _authService.resetPassword(
        email: _email,
        code: _codeController.text.trim(),
        password: _passwordController.text,
        passwordConfirmation: _confirmController.text,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        PasswordResetDone(email: _email, message: message),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.type) {
        case ApiErrorType.badRequest:
          // Wrong / expired code: under the code, which is cleared (the
          // passwords typed are kept).
          _codeController.clear();
          setState(() => _serverErrors = {'code': e.message});
        case ApiErrorType.validation:
          final errors = <String, String>{
            for (final field in const ['code', 'password'])
              if (e.fieldErrors[field] case final messages?)
                field: messages.join('\n'),
          };
          if (errors.isEmpty) {
            _showError(e);
          } else {
            setState(() => _serverErrors = errors);
          }
        default:
          _showError(e, onRetry: _reset);
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Ocurrió un error inesperado. Inténtalo nuevamente.',
        color: SmartBusColors.error,
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  /// Step 2 → step 1, to type another email.
  void _changeEmail() {
    if (_busy) return;
    _cooldownTimer?.cancel();
    setState(() {
      _codeSent = false;
      _cooldownLeft = 0;
      _serverErrors = const {};
    });
  }

  void _startCooldown() {
    setState(() => _cooldownLeft = ForgotPasswordScreen.resendCooldown);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) timer.cancel();
    });
  }

  void _clearServerError(String field) {
    if (!_serverErrors.containsKey(field)) return;
    setState(() => _serverErrors = Map.of(_serverErrors)..remove(field));
  }

  /// Network, timeout, 429, 5xx…: a SnackBar; "Reintentar" when it may work
  /// again right away (not for 429, which needs a wait).
  void _showError(ApiException e, {VoidCallback? onRetry}) {
    final retry = e.type != ApiErrorType.tooManyRequests ? onRetry : null;
    _showMessage(e.message, color: SmartBusColors.error, onRetry: retry);
  }

  void _showMessage(String message, {Color? color, VoidCallback? onRetry}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          action: onRetry == null
              ? null
              : SnackBarAction(
                  label: 'Reintentar',
                  textColor: SmartBusColors.blanco,
                  onPressed: onRetry,
                ),
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
                    28 * scale,
                    25 * scale,
                    27 * scale,
                  ),
                  child: _codeSent
                      ? _buildResetStep(scale)
                      : _buildEmailStep(scale),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double scale) {
    final subtitle = _codeSent
        ? Text.rich(
            TextSpan(
              text: 'Escribe el código de 6 dígitos que enviamos a ',
              children: [
                TextSpan(
                  text: _email,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' y tu nueva contraseña.'),
              ],
            ),
            key: const Key('forgot_sent_to'),
            style: TextStyle(
              color: SmartBusColors.azulCorporativo,
              fontSize: 13 * scale,
            ),
          )
        : Text(
            'Te enviaremos un código a tu correo para crear una nueva '
            'contraseña.',
            style: TextStyle(
              color: SmartBusColors.azulCorporativo,
              fontSize: 13 * scale,
            ),
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        8 * scale,
        8 * scale,
        27 * scale,
        20 * scale,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            key: const Key('forgot_back'),
            tooltip: 'Volver',
            onPressed: _busy ? null : () => Navigator.maybePop(context),
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
                    Flexible(
                      child: Text(
                        'Recuperar contraseña',
                        style: TextStyle(
                          color: SmartBusColors.azulCorporativo,
                          fontSize: 22 * scale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(width: 7 * scale),
                    Icon(
                      Icons.lock_reset,
                      color: SmartBusColors.verdeTurquesa,
                      size: 24 * scale,
                    ),
                  ],
                ),
                SizedBox(height: 5 * scale),
                subtitle,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 1 ------------------------------------------------------------------

  Widget _buildEmailStep(double scale) {
    return Form(
      key: _emailFormKey,
      child: Column(
        children: [
          TextFormField(
            key: const Key('forgot_email'),
            controller: _emailController,
            enabled: !_busy,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            validator: _validateEmail,
            onChanged: (_) => _clearServerError('email'),
            onFieldSubmitted: (_) => _sendCode(),
            decoration: _inputDecoration(
              icon: Icons.person_outline,
              hint: 'Correo electrónico',
              scale: scale,
              serverError: _serverErrors['email'],
            ),
          ),
          SizedBox(height: 28 * scale),
          _GradientButton(
            key: const Key('forgot_send'),
            label: 'Enviar código',
            icon: Icons.send_outlined,
            loading: _sending,
            scale: scale,
            onPressed: _busy ? null : _sendCode,
          ),
          if (_sending) const SlowRequestHint(),
        ],
      ),
    );
  }

  // --- Step 2 ------------------------------------------------------------------

  Widget _buildResetStep(double scale) {
    return Form(
      key: _resetFormKey,
      child: AutofillGroup(
        child: Column(
          children: [
            TextFormField(
              key: const Key('forgot_code'),
              controller: _codeController,
              enabled: !_busy,
              autofocus: true,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 10 * scale,
                color: SmartBusColors.azulCorporativo,
              ),
              validator: _validateCode,
              onChanged: (_) => _clearServerError('code'),
              decoration: _inputDecoration(
                hint: '••••••',
                scale: scale,
                serverError: _serverErrors['code'],
              ).copyWith(prefixIcon: null),
            ),
            SizedBox(height: 8 * scale),
            Text(
              'El código vence en 15 minutos.',
              style: TextStyle(
                fontSize: 12 * scale,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: 18 * scale),
            TextFormField(
              key: const Key('forgot_password'),
              controller: _passwordController,
              enabled: !_busy,
              obscureText: _obscurePassword,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              validator: _validatePassword,
              onChanged: (_) {
                _clearServerError('password');
                if (_confirmController.text.isNotEmpty) {
                  _confirmFieldKey.currentState?.validate();
                }
              },
              decoration: _inputDecoration(
                icon: Icons.lock_outline,
                hint: 'Nueva contraseña',
                scale: scale,
                serverError: _serverErrors['password'],
                suffixIcon: _visibilityToggle(
                  obscured: _obscurePassword,
                  scale: scale,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            PasswordRequirements(controller: _passwordController),
            SizedBox(height: 18 * scale),
            KeyedSubtree(
              key: const Key('forgot_password_confirmation'),
              child: TextFormField(
                key: _confirmFieldKey,
                controller: _confirmController,
                enabled: !_busy,
                obscureText: _obscureConfirm,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textInputAction: TextInputAction.done,
                validator: _validateConfirm,
                onFieldSubmitted: (_) => _reset(),
                decoration: _inputDecoration(
                  icon: Icons.lock_reset_outlined,
                  hint: 'Confirmar nueva contraseña',
                  scale: scale,
                  suffixIcon: _visibilityToggle(
                    obscured: _obscureConfirm,
                    scale: scale,
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
            ),
            SizedBox(height: 28 * scale),
            _GradientButton(
              key: const Key('forgot_submit'),
              label: 'Cambiar contraseña',
              icon: Icons.check_circle_outline,
              loading: _resetting,
              scale: scale,
              onPressed: _busy ? null : _reset,
            ),
            if (_resetting) const SlowRequestHint(),
            SizedBox(height: 14 * scale),
            _buildResend(scale),
            TextButton(
              key: const Key('forgot_change_email'),
              onPressed: _busy ? null : _changeEmail,
              child: const Text('Usar otro correo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResend(double scale) {
    final waiting = _cooldownLeft > 0;
    final label = waiting
        ? 'Reenviar código en ${_formatCooldown(_cooldownLeft)}'
        : 'Reenviar código';
    return Column(
      children: [
        Text(
          '¿No te llegó? Revisa también la carpeta de spam.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5 * scale, color: Colors.grey.shade600),
        ),
        TextButton.icon(
          key: const Key('forgot_resend'),
          onPressed: _busy || waiting ? null : _sendCode,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(label),
        ),
      ],
    );
  }

  static String _formatCooldown(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

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

  /// Same look as the login and sign-up inputs.
  InputDecoration _inputDecoration({
    IconData? icon,
    required String hint,
    required double scale,
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
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: Colors.grey.shade600, size: 20 * scale),
      suffixIcon: suffixIcon,
      // Backend errors; client-side ones come from the validators.
      errorText: serverError,
      errorMaxLines: 4,
      counterText: '',
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
}

/// Blue → turquoise button of the auth screens, with a spinner while
/// [loading].
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.loading,
    required this.scale,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final double scale;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48 * scale,
      child: DecoratedBox(
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
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: loading
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
                    Icon(icon, color: Colors.white, size: 21 * scale),
                    SizedBox(width: 12 * scale),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
