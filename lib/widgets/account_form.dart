import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Pieces shared by the account forms ("Editar perfil", "Cambiar contraseña").
/// Same look as the login / sign-up inputs.

/// Input decoration with a leading icon, a label and an optional backend
/// (422) error; client-side errors come from the field's validator.
InputDecoration accountInputDecoration({
  required IconData icon,
  required String label,
  String? serverError,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
    prefixIcon: Icon(icon, color: Colors.grey.shade600, size: 20),
    suffixIcon: suffixIcon,
    errorText: serverError,
    errorMaxLines: 4,
    filled: true,
    fillColor: const Color(0xFFFAFBFD),
    contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
    border: border(Colors.grey.shade200),
    enabledBorder: border(Colors.grey.shade200),
    disabledBorder: border(Colors.grey.shade200),
    focusedBorder: border(SmartBusColors.verdePasajero, 1.5),
    errorBorder: border(SmartBusColors.error),
    focusedErrorBorder: border(SmartBusColors.error, 1.5),
  );
}

/// Eye button that shows / hides a password field.
class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onPressed,
  });

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: obscured ? 'Mostrar contraseña' : 'Ocultar contraseña',
      onPressed: onPressed,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: Colors.grey.shade600,
        size: 20,
      ),
    );
  }
}

/// Full-width "Guardar" button: spinner and disabled while [isLoading], so a
/// request can never be sent twice.
class AccountSubmitButton extends StatelessWidget {
  const AccountSubmitButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: SmartBusColors.verdePasajero,
        disabledBackgroundColor: SmartBusColors.verdePasajero.withValues(
          alpha: 0.6,
        ),
        minimumSize: const Size(double.infinity, 48),
      ),
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: SmartBusColors.blanco,
                strokeWidth: 2,
              ),
            )
          : Text(label),
    );
  }
}
