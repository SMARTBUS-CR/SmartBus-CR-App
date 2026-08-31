// Requiere el paquete http en pubspec.yaml:
//   dependencies:
//     http: ^1.2.0
//
// Este cliente solo deja listos los endpoints del contrato que compartiste
// (SmartBus Authentication API). Por ahora NO se llama desde las pantallas
// placeholder; lo conectamos cuando el login real esté listo.

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiConfig {
  // TODO: mover a variables de entorno / --dart-define antes de producción
  static const baseUrl =
      'http://smartbus-authentication-dev.onrender.com/api';
}

class AuthApi {
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registerPassenger({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/register/passenger'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
      }),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me(String token) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/user'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> logout(String token) async {
    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/logout'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}
