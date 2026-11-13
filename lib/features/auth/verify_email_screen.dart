import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/slow_request_hint.dart';
import 'role_home.dart';
import 'services/auth_service.dart';

/// Arguments of the `/verify-email` route.
class VerifyEmailArgs {
  const VerifyEmailArgs({
    required this.email,
    this.resendOnOpen = false,
    this.message,
  });

  /// Address the code was (or will be) sent to.
  final String email;

  /// `true` when the screen must request a new code as it opens (e.g. coming
  /// from a login of an unverified account, whose old code may have expired).
  /// After sign-up the backend already sent one, so it stays `false`.
  final bool resendOnOpen;

  /// Optional message to show when the screen opens (e.g. the sign-up one).
  final String? message;
}

/// Email verification with the 6-digit code sent by the Auth service.
///
/// A correct code verifies the email **and signs the user in**
/// ([AuthService.verifyEmail]), so it goes straight to the role's home.
/// "Reenviar código" has a cooldown because the backend allows only 3
/// requests per minute.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.args, this.authService});

  final VerifyEmailArgs args;

  /// Injectable for tests; defaults to a real [AuthService].
  final AuthService? authService;

  /// Seconds before "Reenviar código" can be used again.
  static const resendCooldown = 60;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  bool _isVerifying = false;
  bool _isResending = false;

  /// Backend error for the code (400 wrong/expired/too many, or 422).
  String? _codeError;

  Timer? _cooldownTimer;
  int _cooldownLeft = 0;

  static final _sixDigits = RegExp(r'^\d{6}$');

  String get _email => widget.args.email;

  @override
  void initState() {
    super.initState();
    if (widget.args.resendOnOpen) {
      // The cooldown starts only if this request succeeds, so a failure
      // (e.g. no connection) can be retried right away.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _resend(fromOpen: true),
      );
    } else {
      // Sign-up already sent a code: wait before asking for another one.
      _cooldownLeft = VerifyEmailScreen.resendCooldown;
      _runCooldownTimer();
      final message = widget.args.message;
      if (message != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showMessage(message, color: SmartBusColors.completado),
        );
      }
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  String? _validateCode(String? value) {
    final code = (value ?? '').trim();
    if (code.isEmpty) return 'Ingresa el código que te enviamos';
    if (!_sixDigits.hasMatch(code)) return 'El código tiene 6 dígitos';
    return null;
  }

  // ============================================================
  // ACTIONS
  // ============================================================

  Future<void> _verify() async {
    if (_isVerifying) return;

    FocusScope.of(context).unfocus();
    setState(() => _codeError = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isVerifying = true);
    try {
      final session = await _authService.verifyEmail(
        email: _email,
        code: _codeController.text.trim(),
      );

      if (!mounted) return;
      _showMessage(
        '¡Correo verificado! Bienvenido(a) a SmartBus.',
        color: SmartBusColors.completado,
      );
      // Signed in: clear the stack so "back" does not return here or to login.
      Navigator.pushNamedAndRemoveUntil(
        context,
        homeRouteForUser(session.user) ?? '/passenger/home',
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.type) {
        case ApiErrorType.badRequest:
          // Wrong / expired / too many attempts: belongs under the field.
          setState(() => _codeError = e.message);
        case ApiErrorType.validation:
          final fieldError = e.fieldErrors['code'] ?? e.fieldErrors['email'];
          setState(() => _codeError = fieldError?.join('\n') ?? e.message);
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
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend({bool fromOpen = false}) async {
    if (_isResending || (!fromOpen && _cooldownLeft > 0)) return;

    setState(() => _isResending = true);
    try {
      final message = await _authService.resendVerificationCode(_email);
      if (!mounted) return;
      _codeController.clear();
      setState(() => _codeError = null);
      _startCooldown();
      _showMessage(message, color: SmartBusColors.completado);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showMessage(e.message, color: SmartBusColors.error);
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Ocurrió un error inesperado. Inténtalo nuevamente.',
        color: SmartBusColors.error,
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _startCooldown() {
    setState(() => _cooldownLeft = VerifyEmailScreen.resendCooldown);
    _runCooldownTimer();
  }

  void _runCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) timer.cancel();
    });
  }

  void _showMessage(String message, {Color? color}) {
    // Replace (not queue behind) a previous message, e.g. "código enviado".
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
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
    final busy = _isVerifying || _isResending;

    return Scaffold(
      backgroundColor: SmartBusColors.grisClaro,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(scale, busy),
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
                    30 * scale,
                    25 * scale,
                    27 * scale,
                  ),
                  child: _buildForm(scale, busy),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double scale, bool busy) {
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
            tooltip: 'Volver',
            onPressed: busy ? null : () => Navigator.maybePop(context),
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
                        'Verifica tu correo',
                        style: TextStyle(
                          color: SmartBusColors.azulCorporativo,
                          fontSize: 22 * scale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(width: 7 * scale),
                    Icon(
                      Icons.mark_email_read_outlined,
                      color: SmartBusColors.verdeTurquesa,
                      size: 24 * scale,
                    ),
                  ],
                ),
                SizedBox(height: 5 * scale),
                Text.rich(
                  TextSpan(
                    text: 'Escribe el código de 6 dígitos que enviamos a ',
                    children: [
                      TextSpan(
                        text: _email,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
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

  Widget _buildForm(double scale, bool busy) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            key: const Key('verify_code'),
            controller: _codeController,
            enabled: !busy,
            autofocus: true,
            // Real-time: validates as soon as the user types.
            autovalidateMode: AutovalidateMode.onUserInteraction,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26 * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: 12 * scale,
              color: SmartBusColors.azulCorporativo,
            ),
            validator: _validateCode,
            onChanged: (_) {
              if (_codeError != null) setState(() => _codeError = null);
            },
            onFieldSubmitted: (_) => _verify(),
            decoration: _codeDecoration(scale),
          ),

          SizedBox(height: 10 * scale),
          Text(
            'El código vence en 15 minutos.',
            style: TextStyle(fontSize: 12 * scale, color: Colors.grey.shade600),
          ),

          SizedBox(height: 26 * scale),
          _buildVerifyButton(scale, busy),
          if (_isVerifying) const SlowRequestHint(),

          SizedBox(height: 18 * scale),
          _buildResend(scale, busy),
        ],
      ),
    );
  }

  InputDecoration _codeDecoration(double scale) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: '••••••',
      hintStyle: TextStyle(
        color: Colors.grey.shade400,
        letterSpacing: 12 * scale,
      ),
      counterText: '',
      // Backend (400/422) error; client-side ones come from the validator.
      errorText: _codeError,
      errorMaxLines: 3,
      filled: true,
      fillColor: const Color(0xFFFAFBFD),
      contentPadding: EdgeInsets.symmetric(vertical: 16 * scale),
      border: border(Colors.grey.shade200),
      enabledBorder: border(Colors.grey.shade200),
      disabledBorder: border(Colors.grey.shade200),
      focusedBorder: border(SmartBusColors.azulPrincipal, 1.5),
      errorBorder: border(SmartBusColors.error),
      focusedErrorBorder: border(SmartBusColors.error, 1.5),
    );
  }

  Widget _buildVerifyButton(double scale, bool busy) {
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
          key: const Key('verify_submit'),
          onPressed: busy ? null : _verify,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: _isVerifying
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
                    Icon(Icons.verified, color: Colors.white, size: 21 * scale),
                    SizedBox(width: 12 * scale),
                    Text(
                      'Verificar',
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

  Widget _buildResend(double scale, bool busy) {
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
          key: const Key('verify_resend'),
          onPressed: busy || waiting ? null : _resend,
          icon: _isResending
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
}
