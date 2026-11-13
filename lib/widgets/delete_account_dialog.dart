import 'package:flutter/material.dart';

import '../core/network/api_exception.dart';
import '../core/theme.dart';

/// Sends the deletion request with the current password and returns the
/// message to show on success (see `AuthService.deleteAccount`).
typedef DeleteAccountRequest = Future<String> Function(String currentPassword);

/// What [DeleteAccountDialog] pops with. `null` means the user cancelled.
class DeleteAccountOutcome {
  const DeleteAccountOutcome.deleted(String this.message) : error = null;
  const DeleteAccountOutcome.failed(ApiException this.error) : message = null;

  /// Backend message when the account was deleted.
  final String? message;

  /// Error the dialog cannot recover from (401 / 403): the caller handles it.
  final ApiException? error;
}

/// "¿Eliminar tu cuenta?" confirmation.
///
/// The backend requires the current password, so it is asked here. The dialog
/// sends the request itself and:
/// - stays open on a wrong password (422), too many attempts (429) or a
///   network error, so the user can retry;
/// - pops [DeleteAccountOutcome.deleted] on success;
/// - pops [DeleteAccountOutcome.failed] on 401 / 403.
///
/// While the request is running it cannot be dismissed.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.onDelete});

  final DeleteAccountRequest onDelete;

  static Future<DeleteAccountOutcome?> show(
    BuildContext context,
    DeleteAccountRequest onDelete,
  ) {
    return showDialog<DeleteAccountOutcome>(
      context: context,
      builder: (_) => DeleteAccountDialog(onDelete: onDelete),
    );
  }

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _deleting = false;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _passwordError = 'Ingresa tu contraseña.');
      return;
    }

    setState(() {
      _deleting = true;
      _passwordError = null;
      _error = null;
    });

    try {
      final message = await widget.onDelete(password);
      if (!mounted) return;
      Navigator.pop(context, DeleteAccountOutcome.deleted(message));
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.type) {
        case ApiErrorType.unauthorized:
        case ApiErrorType.forbidden:
        case ApiErrorType.emailNotVerified:
          Navigator.pop(context, DeleteAccountOutcome.failed(e));
        case ApiErrorType.validation:
          setState(() {
            _deleting = false;
            _passwordError =
                e.fieldErrors['current_password']?.first ?? e.message;
          });
        default:
          setState(() {
            _deleting = false;
            _error = e.message;
          });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'No se pudo eliminar tu cuenta. Inténtalo nuevamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_deleting,
      child: AlertDialog(
        key: const Key('delete_account_dialog'),
        title: const Text('¿Eliminar tu cuenta?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('¿Estás seguro? Esta acción no se puede deshacer.'),
              const SizedBox(height: 16),
              Text(
                'Para confirmar, ingresa tu contraseña.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('delete_account_password'),
                controller: _password,
                obscureText: _obscure,
                enabled: !_deleting,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Contraseña actual',
                  errorText: _passwordError,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? 'Mostrar contraseña'
                        : 'Ocultar contraseña',
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('delete_account_error'),
                  style: const TextStyle(color: SmartBusColors.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('delete_account_cancel'),
            onPressed: _deleting ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('delete_account_confirm'),
            style: TextButton.styleFrom(foregroundColor: SmartBusColors.error),
            onPressed: _deleting ? null : _submit,
            child: _deleting
                ? const SizedBox(
                    key: Key('delete_account_progress'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
