import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../apis/auth_api.dart';
import '../../../models/user_model.dart';

final authApiProvider = Provider<AuthApi>((ref) => AuthApi());

/// Kept for the lifetime of the app's ProviderScope, across route changes.
final userSessionProvider = ChangeNotifierProvider<UserSession>((ref) {
  return UserSession(ref.watch(authApiProvider));
});

/// Watch this in any ConsumerWidget to render the current user's profile.
final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(userSessionProvider).user;
});

class UserSession extends ChangeNotifier {
  UserSession(this._api) {
    // Firebase persists the credentials. The initial auth event restores the
    // Firestore profile; no local role/status copy is trusted for access.
    _authSubscription = _api.authChanges().listen(
      (account) => _follow(account?.uid),
      onError: (Object error) {
        _stopProfile();
        _set(const AsyncData(null), failure: error);
      },
    );
  }
  final AuthApi _api;
  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<UserModel?>? _profileSubscription;
  AsyncValue<UserModel?> _state = const AsyncLoading();
  String? _uid;
  int _generation = 0;
  bool _disposed = false;
  AsyncValue<UserModel?> get state => _state;
  UserModel? get user => _state.asData?.value;
  bool get isSignedIn => _uid != null;

  void _set(AsyncValue<UserModel?> value, {Object? failure}) {
    if (_disposed) return;
    _state = failure == null ? value : AsyncError(failure, StackTrace.current);
    notifyListeners();
  }

  void _stopProfile() {
    _generation++;
    _profileSubscription?.cancel();
    _profileSubscription = null;
  }

  void _follow(String? uid, {UserModel? initial, bool force = false}) {
    if (_disposed) return;
    if (!force && uid != null && uid == _uid && _profileSubscription != null) {
      if (initial != null) _set(AsyncData(initial));
      return;
    }
    _stopProfile();
    _uid = uid;
    if (uid == null) {
      _set(const AsyncData(null));
      return;
    }
    _set(initial == null ? const AsyncLoading() : AsyncData(initial));
    final generation = _generation;
    _profileSubscription = _api
        .watchUserProfile(uid)
        .listen(
          (profile) {
            if (!_disposed && generation == _generation) {
              _set(AsyncData(profile));
            }
          },
          onError: (Object error) {
            if (!_disposed && generation == _generation) {
              _set(const AsyncData(null), failure: error);
            }
          },
        );
  }

  /// Called only with a profile fetched and validated by AuthController.
  void setUser(UserModel profile) => _follow(profile.uid, initial: profile);
  void refresh() => _follow(_api.currentUser?.uid, force: true);
  void clear() => _follow(null, force: true);

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    _stopProfile();
    super.dispose();
  }
}
