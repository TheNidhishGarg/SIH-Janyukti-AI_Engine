import '../providers/user_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../apis/auth_api.dart';
import '../../../core/routes/app_routes.dart';
import '../../../models/registration_data.dart';
import '../../../models/user_model.dart';
import '../../../models/user_role.dart';

final authControllerProvider =
    ChangeNotifierProvider.autoDispose<AuthController>(
      (ref) => AuthController(
        api: ref.watch(authApiProvider),
        session: ref.read(userSessionProvider),
      ),
    );

String authErrorMessage(Object error) {
  if (error is AccountException) return error.message;
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'wrong-password' ||
      'invalid-credential' ||
      'user-not-found' => 'Invalid email or password.',
      'email-already-in-use' => 'An account already exists with this email.',
      'weak-password' => 'Password must contain at least 6 characters.',
      'too-many-requests' => 'Too many attempts. Please wait and try again.',
      'network-request-failed' =>
        'Unable to connect. Check your internet connection.',
      'user-disabled' =>
        'Your account has been disabled. Contact the janYukti administrator.',
      'operation-not-allowed' =>
        'Email/password sign-in is currently unavailable.',
      'invalid-verification-code' => 'The OTP is incorrect or has expired.',
      _ => 'Authentication failed. Please try again.',
    };
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Access denied. Contact the janYukti administrator.',
      'unavailable' || 'deadline-exceeded' =>
        'Unable to connect. Check your internet connection.',
      _ => 'Unable to save or load account information. Please try again.',
    };
  }
  return 'Unable to load your account. Please try again or contact the janYukti administrator.';
}

class AuthController extends ChangeNotifier {
  AuthController({AuthApi? api, UserSession? session})
    : _api = api ?? AuthApi(),
      _session = session;
  final UserSession? _session;
  final AuthApi _api;
  bool isLoading = false, _disposed = false;
  String? errorMessage;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void clearError() {
    errorMessage = null;
    _notify();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (isLoading) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      await action();
    } catch (error) {
      errorMessage = authErrorMessage(error);
    } finally {
      isLoading = false;
      _notify();
    }
  }

  Future<void> loginWithEmail(
    BuildContext context,
    UserRole role,
    String email,
    String password,
  ) => _run(() async {
    if (!RegistrationData.validEmail(email) || password.isEmpty) {
      throw const AccountException('Enter your email and password.');
    }
    await _api.login(email: email, password: password);
    try {
      final profile = await _api.requireProfile(role);
      _session?.setUser(profile);
      if (context.mounted) routeProfile(context, profile);
    } catch (_) {
      _session?.clear();
      await _api.logout();
      rethrow;
    }
  });
  Future<void> register(BuildContext context, RegistrationData data) =>
      _run(() async {
        final profile = await switch (data.role) {
          UserRole.citizen => _api.registerCitizen(data),
          UserRole.admin => _api.registerAdmin(data),
          UserRole.university ||
          UserRole.industry => _api.registerOrganization(data),
        };
        _session?.setUser(profile);
        if (context.mounted) routeProfile(context, profile);
      });
  Future<void> sendPasswordReset(String email) async {
    if (isLoading) return;
    await _run(() async {
      if (!RegistrationData.validEmail(email)) {
        throw const AccountException('Enter a valid email address first.');
      }
      await _api.resetPassword(email);
    });
  }

  Future<void> logout(BuildContext context) => _run(() async {
    await _api.logout();
    _session?.clear();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        Routes.roleSelection,
        (_) => false,
      );
    }
  });
  void routeProfile(BuildContext context, UserModel profile) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      profile.isActive ? dashboardRoute(profile.role) : Routes.pending,
      (_) => false,
    );
  }

  static String dashboardRoute(UserRole role) => switch (role) {
    UserRole.citizen => Routes.citizen,
    UserRole.university => Routes.university,
    UserRole.industry => Routes.industry,
    UserRole.admin => Routes.admin,
  };
  // Legacy OTP entry can only authenticate an existing active citizen profile.
  Future<bool> verifyCitizenOtp(String verificationId, String code) async {
    var verified = false;
    await _run(() async {
      await _api.verifyOtp(verificationId, code);
      try {
        final profile = await _api.requireProfile(UserRole.citizen);
        if (!profile.isActive) {
          throw const AccountException(
            'This account is not active. Sign in with email to view its status.',
          );
        }
        verified = true;
      } catch (_) {
        await _api.logout();
        rethrow;
      }
    });
    return verified;
  }

  void openDashboard(BuildContext context, UserRole role) =>
      Navigator.pushNamedAndRemoveUntil(
        context,
        dashboardRoute(role),
        (_) => false,
      );
}
