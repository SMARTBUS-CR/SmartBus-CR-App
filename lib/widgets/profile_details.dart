import 'package:flutter/material.dart';

import '../core/network/api_exception.dart';
import '../core/storage/secure_session_store.dart';
import '../core/theme.dart';
import '../features/auth/models/auth_user.dart';
import '../features/auth/services/auth_service.dart';
import 'smartbus_header.dart';

/// Read-only "Mi Cuenta" view shared by the passenger and driver flows.
///
/// The user stored at login is shown right away (never an empty screen) and
/// then refreshed with `GET {gateway}/auth/user?include=roles`:
/// - 401 → the local session is cleared and the user goes back to login.
/// - No connection / timeout / 5xx → the stored data stays visible with a
///   "Reintentar" action.
///
/// No field is editable. The only other request it sends is
/// `POST /auth/logout` from the "Cerrar sesión" button.
///
/// With [onDeleteAccount], an "Eliminar cuenta" button is shown; it asks for
/// confirmation and only then calls [onDeleteAccount].
class ProfileDetails extends StatefulWidget {
  const ProfileDetails({
    super.key,
    required this.color,
    required this.role,
    required this.homeRoute,
    required this.bottomNavigationBar,
    this.readOnlyNotice,
    this.onDeleteAccount,
    this.authService,
    this.sessionStore,
  });

  /// Accent color of the flow (header, avatar, icons).
  final Color color;

  /// Role whose label is shown first (`passenger`, `driver`).
  final String role;

  /// Route opened by the back arrow.
  final String homeRoute;

  final Widget bottomNavigationBar;

  /// Optional notice shown under the profile (e.g. who can change the data).
  final String? readOnlyNotice;

  /// Called after the user confirms "Eliminar cuenta". When null (drivers),
  /// the button is not shown.
  final VoidCallback? onDeleteAccount;

  /// Injectable for tests; defaults to a real [AuthService].
  final AuthService? authService;

  /// Injectable for tests; defaults to a real [SecureSessionStore].
  final SecureSessionStore? sessionStore;

  @override
  State<ProfileDetails> createState() => _ProfileDetailsState();
}

class _ProfileDetailsState extends State<ProfileDetails> {
  static const _sessionExpiredMessage =
      'Tu sesión expiró. Inicia sesión nuevamente.';

  late final SecureSessionStore _session =
      widget.sessionStore ?? SecureSessionStore();
  late final AuthService _authService =
      widget.authService ?? AuthService(sessionStore: _session);

  AuthUser? _user;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ============================================================
  // DATA
  // ============================================================

  /// Shows the stored user first, then asks the backend for fresh data.
  Future<void> _load() async {
    final stored = await _session.readUser();
    if (!mounted) return;
    if (stored != null) {
      setState(() => _user = AuthUser.fromStorage(stored));
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _authService.fetchCurrentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.type == ApiErrorType.unauthorized) {
        await _onSessionExpired();
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'No se pudo cargar tu perfil. Inténtalo nuevamente.';
      });
    }
  }

  Future<void> _onSessionExpired() async {
    // The token is already invalid: no need to call POST /auth/logout.
    await _session.clear();
    if (!mounted) return;
    _showMessage(_sessionExpiredMessage, color: SmartBusColors.error);
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('delete_account_dialog'),
        title: const Text('¿Eliminar tu cuenta?'),
        content: const Text('¿Estás seguro? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            key: const Key('delete_account_cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('delete_account_confirm'),
            style: TextButton.styleFrom(foregroundColor: SmartBusColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    // Tapping outside or pressing back returns null: same as "Cancelar".
    if (confirmed == true && mounted) widget.onDeleteAccount?.call();
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
      bottomNavigationBar: widget.bottomNavigationBar,
      body: Column(
        children: [
          SmartBusHeader(
            title: 'Mi Cuenta',
            type: widget.role == 'driver'
                ? SmartBusUserType.driver
                : SmartBusUserType.passenger,
            onBack: () =>
                Navigator.pushReplacementNamed(context, widget.homeRoute),
          ),
          // Refreshing over the stored data: thin bar instead of hiding the
          // profile behind a spinner.
          SizedBox(
            height: 3,
            child: _isLoading && _user != null
                ? LinearProgressIndicator(
                    key: const Key('profile_refreshing'),
                    minHeight: 3,
                    color: widget.color,
                    backgroundColor: Colors.transparent,
                  )
                : null,
          ),
          Expanded(child: _buildContent()),
          if (widget.onDeleteAccount != null) _buildDeleteAccountButton(),
          _buildLogoutButton(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final user = _user;

    // Nothing stored (should not happen after login): spinner or error only.
    if (user == null) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _buildErrorNotice(
            _errorMessage ?? 'No se pudo cargar tu perfil.',
          ),
        ),
      );
    }

    final roleLabel = _roleLabelOf(user);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      children: [
        Center(child: _buildAvatar(user)),
        const SizedBox(height: 16),
        Text(
          user.name,
          key: const Key('profile_name'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: SmartBusColors.grisOscuro,
          ),
        ),
        if (roleLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(child: _buildRoleChip(roleLabel)),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 20),
          _buildErrorNotice(_errorMessage!),
        ],
        const SizedBox(height: 24),
        _buildInfoTile(
          icon: Icons.email_outlined,
          label: 'Correo electrónico',
          child: Text(
            user.email,
            key: const Key('profile_email'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        if (widget.readOnlyNotice != null) ...[
          const SizedBox(height: 4),
          _buildReadOnlyNotice(widget.readOnlyNotice!),
        ],
      ],
    );
  }

  Widget _buildAvatar(AuthUser user) {
    final initials = _initialsOf(user);
    return CircleAvatar(
      key: const Key('profile_avatar'),
      radius: 40,
      backgroundColor: widget.color,
      foregroundColor: SmartBusColors.blanco,
      child: initials.isEmpty
          ? const Icon(Icons.person, size: 40)
          : Text(
              initials,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
    );
  }

  Widget _buildRoleChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        key: const Key('profile_role'),
        style: TextStyle(color: widget.color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SmartBusColors.grisClaro,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: widget.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyNotice(String message) {
    return Row(
      key: const Key('profile_read_only_notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorNotice(String message) {
    return Container(
      key: const Key('profile_error'),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: SmartBusColors.advertencia.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: SmartBusColors.advertencia),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(
            key: const Key('profile_retry'),
            onPressed: _isLoading ? null : _refresh,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  /// Secondary, red-text action: clearly different from "Cerrar sesión".
  Widget _buildDeleteAccountButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: TextButton.icon(
        key: const Key('profile_delete_account'),
        style: TextButton.styleFrom(
          foregroundColor: SmartBusColors.error,
          minimumSize: const Size(double.infinity, 44),
        ),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Eliminar cuenta'),
        onPressed: _confirmDeleteAccount,
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ElevatedButton.icon(
        key: const Key('profile_logout'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          minimumSize: const Size(double.infinity, 48),
        ),
        icon: const Icon(Icons.logout),
        label: const Text('Cerrar sesión'),
        onPressed: _logout,
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// "Ana María Pérez" → "AP"; a single word → its first letter.
  /// Falls back to the email's first letter, or empty (person icon).
  static String _initialsOf(AuthUser user) {
    final words = user.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      final email = user.email.trim();
      return email.isEmpty ? '' : email.characters.first.toUpperCase();
    }

    final first = words.first.characters.first;
    final last = words.length > 1 ? words.last.characters.first : '';
    return '$first$last'.toUpperCase();
  }

  /// Label of [ProfileDetails.role] ("Pasajero", "Conductor"), or of the
  /// first role.
  String _roleLabelOf(AuthUser user) {
    final role =
        user.roles.where((r) => r.value == widget.role).firstOrNull ??
        user.primaryRole;
    if (role == null) return '';
    return role.label.isNotEmpty ? role.label : role.value;
  }
}
