// lib/apis/auth_api.dart — real replacement for the demoLogin() stub.

import '../models/user_model.dart';
import '../models/user_role.dart';
import 'api_client.dart';

class AuthApi {
  final _api = ApiClient.instance;

  Future<UserModel> login(String email, String password) async {
    final data = await _api.post('/auth/login', body: {
      'email': email.trim(),
      'password': password,
    });
    await _api.setToken(data['access_token'] as String);
    final user = data['user'] as Map<String, dynamic>;
    return UserModel(user['name'] as String, user['role'] as String);
  }

  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? universityId,
    String? industryId,
  }) async {
    final data = await _api.post('/auth/register', body: {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'role': role.name,
      if (universityId != null) 'university_id': universityId,
      if (industryId != null) 'industry_id': industryId,
    });
    await _api.setToken(data['access_token'] as String);
    final user = data['user'] as Map<String, dynamic>;
    return UserModel(user['name'] as String, user['role'] as String);
  }

  /// Dev OTP flow, so the existing OTP screen works without an SMS gateway.
  /// The backend returns the code in the message while DEBUG=true.
  Future<void> requestOtp(String phone) =>
      _api.post('/auth/otp/request', body: {'phone': phone});

  Future<UserModel> verifyOtp(String phone, String otp, {String? name}) async {
    final data = await _api.post('/auth/otp/verify', body: {
      'phone': phone,
      'otp': otp,
      if (name != null) 'name': name,
    });
    await _api.setToken(data['access_token'] as String);
    final user = data['user'] as Map<String, dynamic>;
    return UserModel(user['name'] as String, user['role'] as String);
  }

  /// Call on app start: validates a stored token and restores the session.
  Future<UserModel?> restoreSession() async {
    await _api.loadToken();
    if (!_api.isAuthenticated) return null;
    try {
      final user = await _api.get('/auth/me') as Map<String, dynamic>;
      return UserModel(user['name'] as String, user['role'] as String);
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _api.setToken(null); // expired
      return null;
    }
  }

  Future<void> logout() => _api.setToken(null);
}
