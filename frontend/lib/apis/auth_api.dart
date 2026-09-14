import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../models/registration_data.dart';

class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
}

class AuthApi {
  AuthApi({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  User? get currentUser => _auth.currentUser;
  Stream<User?> authChanges() => _auth.authStateChanges();
  Future<UserCredential> login({
    required String email,
    required String password,
  }) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  Future<UserCredential> verifyOtp(String verificationId, String code) =>
      _auth.signInWithCredential(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: code,
        ),
      );
  Future<void> logout() => _auth.signOut();
  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
  Future<UserModel?> getUserProfile(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return doc.exists ? UserModel.fromMap(uid, doc.data()!) : null;
  }

  Stream<UserModel?> watchUserProfile(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .map((doc) {
        // Never grant dashboard access using a stale cached approval.
        if (doc.metadata.isFromCache) return null;
        return doc.exists ? UserModel.fromMap(uid, doc.data()!) : null;
      });
  Future<UserModel> requireProfile(UserRole? selectedRole) async {
    final user = currentUser;
    if (user == null) throw const AccountException('Please sign in again.');
    final profile = await getUserProfile(user.uid);
    if (profile == null) {
      throw const AccountException(
        'Your account profile is missing. Please contact the janYukti administrator.',
      );
    }
    if (selectedRole != null && profile.role != selectedRole) {
      await logout();
      throw const AccountException(
        'This account does not belong to the selected portal.',
      );
    }
    return profile;
  }

  Future<UserModel> registerCitizen(RegistrationData data) =>
      _register(data, UserRole.citizen);
  Future<UserModel> registerAdmin(RegistrationData data) =>
      _register(data, UserRole.admin);
  Future<UserModel> registerOrganization(RegistrationData data) {
    if (!data.isOrganization) {
      throw const AccountException('Choose a university or industry portal.');
    }
    return _register(data, data.role);
  }

  Future<UserModel> _register(
    RegistrationData data,
    UserRole expectedRole,
  ) async {
    if (data.role != expectedRole) {
      throw const AccountException('Invalid registration role.');
    }
    final error = data.validate();
    if (error != null) throw AccountException(error);
    final credential = await _auth.createUserWithEmailAndPassword(
      email: data.email.trim(),
      password: data.password,
    );
    final user = credential.user!;
    final org = data.isOrganization
        ? _db.collection('organizations').doc()
        : null;
    final timestamp = FieldValue.serverTimestamp();
    final profile = UserModel(
      uid: user.uid,
      role: data.role,
      fullName: data.fullName.trim(),
      email: data.email.trim(),
      phone: data.phone.trim(),
      status: data.role == UserRole.citizen ? 'active' : 'pending',
      city: data.city.trim(),
      state: data.state.trim(),
      designation: data.designation.trim(),
      organizationId: org?.id,
    );
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(user.uid), {
      ...profile.toMap(),
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
    if (org != null) {
      batch.set(org, {
        'id': org.id,
        'name': data.organizationName.trim(),
        'type': data.role.name,
        if (data.role == UserRole.university)
          'organizationCategory': data.category,
        if (data.role == UserRole.industry) 'sector': data.category,
        'officialEmail': data.email.trim(),
        'phone': data.phone.trim(),
        'website': data.website.trim(),
        'address': data.address.trim(),
        'city': data.city.trim(),
        'state': data.state.trim(),
        'status': 'pending',
        'createdBy': user.uid,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      });
    }
    try {
      await batch.commit();
    } catch (_) {
      // Auth and Firestore cannot share a transaction. Remove the new Auth account
      // when the atomic profile/organization write fails, allowing a clean retry.
      try {
        await user.delete();
      } catch (_) {
        await logout();
        throw const AccountException(
          'Registration could not finish. Contact the janYukti administrator to recover this account before retrying.',
        );
      }
      await logout();
      rethrow;
    }
    return profile;
  }
}
