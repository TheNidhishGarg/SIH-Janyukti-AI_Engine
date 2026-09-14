import 'package:firebase_auth/firebase_auth.dart';
import '../../../apis/auth_api.dart';
import '../../../models/user_model.dart';
import '../../../models/user_role.dart';

/// Compatibility facade: sign-in must never create a profile from a portal selection.
class UserProfileService {
  Future<UserModel> ensureProfile(User firebaseUser, UserRole selectedRole) =>
      AuthApi().requireProfile(selectedRole);
}
