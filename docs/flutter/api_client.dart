// lib/apis/api_client.dart
//
// Single HTTP client for the JanYukti backend: base URL, JSON encoding, the
// bearer token, and error handling all live here so the per-feature API classes
// stay thin.
//
// Add to pubspec.yaml:
//   http: ^1.2.0
//   shared_preferences: ^2.2.0

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// Android emulator reaches the host machine at 10.0.2.2, not localhost.
  /// For a physical device use the machine LAN IP, e.g. http://192.168.1.5:8000
  /// Override at build time:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const _tokenKey = 'janyukti_token';
  String? _token;

  String? get token => _token;
  bool get isAuthenticated => _token != null;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<void> setToken(String? value) async {
    _token = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, value);
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleaned = query?.map((k, v) => MapEntry(k, '$v'))
      ?..removeWhere((_, v) => v.isEmpty || v == 'null');
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: (cleaned?.isEmpty ?? true) ? null : cleaned,
    );
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => http.post(_uri(path, query),
          headers: _headers, body: body == null ? null : jsonEncode(body)));

  Future<dynamic> patch(String path, {Object? body}) => _send(
      () => http.patch(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 30));
    } catch (e) {
      throw ApiException(0, 'Cannot reach the server. Check your connection. ($e)');
    }

    final body = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _extractError(body, response.statusCode));
    }
    return body;
  }

  /// FastAPI returns `{"detail": "..."}` for handled errors, but a list of
  /// field errors for 422 validation failures. Flatten both to one string.
  String _extractError(dynamic body, int status) {
    if (body is Map && body['detail'] != null) {
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map) {
          final loc = (first['loc'] as List?)?.last;
          return '${loc ?? 'Field'}: ${first['msg'] ?? 'invalid'}';
        }
      }
    }
    return 'Request failed ($status)';
  }
}
