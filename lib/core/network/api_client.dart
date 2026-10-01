import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../storage/secure_session_store.dart';
import 'api_exception.dart';

/// Reusable HTTP client for the whole app.
///
/// Responsibilities:
/// - Always use the API Gateway as the base (see [ApiConfig]).
/// - Inject the common headers (`Content-Type`, `Accept`, `Accept-Language`).
/// - Automatically inject `Authorization: Bearer <token>` when a session is
///   stored — no service needs to add the token by hand.
/// - Translate network errors and HTTP status codes into [ApiException] with
///   user-friendly messages.
///
/// When `/trips`, `/gps`, `/eta`, … are added, each service reuses this same
/// client unchanged.
class ApiClient {
  ApiClient({SecureSessionStore? sessionStore, http.Client? httpClient})
      : _session = sessionStore ?? SecureSessionStore(),
        _http = httpClient ?? http.Client();

  final SecureSessionStore _session;
  final http.Client _http;

  Future<Map<String, dynamic>> get(Uri url) => _send('GET', url);

  Future<Map<String, dynamic>> post(Uri url, {Object? body}) =>
      _send('POST', url, body: body);

  Future<Map<String, dynamic>> put(Uri url, {Object? body}) =>
      _send('PUT', url, body: body);

  Future<Map<String, dynamic>> delete(Uri url, {Object? body}) =>
      _send('DELETE', url, body: body);

  Future<Map<String, dynamic>> _send(
    String method,
    Uri url, {
    Object? body,
  }) async {
    final request = http.Request(method, url)
      ..headers.addAll(await _buildHeaders());
    if (body != null) request.body = jsonEncode(body);

    try {
      final streamed =
          await _http.send(request).timeout(ApiConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      return _handle(response);
    } on TimeoutException {
      throw ApiException.timeout;
    } on SocketException {
      throw ApiException.noConnection;
    } on http.ClientException {
      throw ApiException.noConnection;
    } on HandshakeException {
      throw ApiException.noConnection;
    }
  }

  Future<Map<String, String>> _buildHeaders() async {
    final token = await _session.readToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Accept-Language': ApiConfig.language,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _handle(http.Response response) {
    final status = response.statusCode;
    final body = _decode(response.body);

    if (status >= 200 && status < 300) return body;

    throw ApiException.fromStatus(
      status,
      serverMessage: _messageFrom(body),
      fieldErrors: _fieldErrorsFrom(body),
    );
  }

  Map<String, dynamic> _decode(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    } catch (_) {
      return const {};
    }
  }

  /// Extracts a safe message from an error body.
  ///
  /// Supported formats:
  /// - JSON:API (Auth and GPS services): `{"errors": [{"detail": "..."}]}`
  /// - Laravel (Gateway): `{"message": "..."}` or `{"errors": {"field": ["..."]}}`
  String? _messageFrom(Map<String, dynamic> body) {
    final errors = body['errors'];

    if (errors is List) {
      for (final error in errors.whereType<Map>()) {
        final detail = error['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
      }
    }

    final message = body['message'];
    if (message is String && message.isNotEmpty) return message;

    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (errors['detail'] is String) return errors['detail'] as String;
    }
    return null;
  }

  /// Extracts the validation errors of each field (422).
  ///
  /// - JSON:API: each error points to its field with
  ///   `source.pointer = "/data/attributes/<field>"`.
  /// - Laravel: `{"errors": {"<field>": ["message", …]}}`.
  Map<String, List<String>> _fieldErrorsFrom(Map<String, dynamic> body) {
    final errors = body['errors'];
    final result = <String, List<String>>{};

    if (errors is List) {
      for (final error in errors.whereType<Map>()) {
        final source = error['source'];
        final pointer = source is Map ? source['pointer'] : null;
        final detail = error['detail'];
        if (pointer is! String || pointer.isEmpty || detail is! String) {
          continue;
        }
        final field = pointer.split('/').last;
        (result[field] ??= []).add(detail);
      }
    } else if (errors is Map) {
      errors.forEach((field, messages) {
        if (messages is List) {
          result[field.toString()] =
              messages.map((m) => m.toString()).toList();
        }
      });
    }

    return result;
  }

  void close() => _http.close();
}
