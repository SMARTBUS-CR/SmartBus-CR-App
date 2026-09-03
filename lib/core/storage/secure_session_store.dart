import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for the session: access token + user data.
///
/// - The token is stored in the system Keystore (Android) / Keychain (iOS) via
///   `flutter_secure_storage`. Never in plain text or in source code.
/// - **The password is never stored.**
/// - Designed so [readToken] can automatically feed the `Authorization` header
///   of every request (see `ApiClient`).
class SecureSessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kToken = 'sb_access_token';
  static const _kTokenType = 'sb_token_type';
  static const _kUser = 'sb_user';

  // --- Token ---------------------------------------------------------------

  Future<void> saveToken(String token, {String tokenType = 'Bearer'}) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kTokenType, value: tokenType);
  }

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<String?> readTokenType() => _storage.read(key: _kTokenType);

  Future<bool> hasSession() async {
    final token = await readToken();
    return token != null && token.isNotEmpty;
  }

  // --- User --------------------------------------------------------------

  Future<void> saveUser(Map<String, dynamic> userJson) =>
      _storage.write(key: _kUser, value: jsonEncode(userJson));

  Future<Map<String, dynamic>?> readUser() async {
    final raw = await _storage.read(key: _kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  // --- Cleanup ---------------------------------------------------------

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kTokenType);
    await _storage.delete(key: _kUser);
  }
}
