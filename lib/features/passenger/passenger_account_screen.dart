import 'package:flutter/material.dart';

import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../../widgets/passenger_bottom_nav.dart';
import '../../widgets/profile_details.dart';
import '../auth/services/auth_service.dart';

/// Passenger "Mi Cuenta" tab: read-only profile of the signed-in user.
///
/// Read-only: passengers have no self-update endpoint yet. Loading, 401 and
/// retry handling live in [ProfileDetails].
class PassengerAccountScreen extends StatelessWidget {
  const PassengerAccountScreen({
    super.key,
    this.authService,
    this.sessionStore,
  });

  /// Injectable for tests; defaults to a real [AuthService].
  final AuthService? authService;

  /// Injectable for tests; defaults to a real [SecureSessionStore].
  final SecureSessionStore? sessionStore;

  @override
  State<PassengerAccountScreen> createState() => _PassengerAccountScreenState();
}

class _PassengerAccountScreenState extends State<PassengerAccountScreen> {
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

  void _showMessage(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
      ),
    );
  }

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/passenger/home');
        return;
      case 1:
        Navigator.pushReplacementNamed(context, '/passenger/trips');
        return;
      case 2:
        return; // already on Account
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return ProfileDetails(
      color: SmartBusColors.verdePasajero,
      role: 'passenger',
      homeRoute: '/passenger/home',
      authService: authService,
      sessionStore: sessionStore,
      bottomNavigationBar: PassengerBottomNav(
        currentIndex: 2,
        onTap: (index) => _onTabTap(context, index),
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
      ],
    );
  }

  Widget _buildAvatar(AuthUser user) {
    final initials = _initialsOf(user);
    return CircleAvatar(
      key: const Key('profile_avatar'),
      radius: 40,
      backgroundColor: SmartBusColors.verdeMenta,
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
        color: SmartBusColors.verdeMenta.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        key: const Key('profile_role'),
        style: const TextStyle(
          color: SmartBusColors.verdeMenta,
          fontWeight: FontWeight.w600,
        ),
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
          Icon(icon, color: SmartBusColors.verdeMenta),
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

  /// Label of the passenger role ("Pasajero"), or of the first role.
  static String _roleLabelOf(AuthUser user) {
    final role =
        user.roles.where((r) => r.value == 'passenger').firstOrNull ??
        user.primaryRole;
    if (role == null) return '';
    return role.label.isNotEmpty ? role.label : role.value;
  }
}
