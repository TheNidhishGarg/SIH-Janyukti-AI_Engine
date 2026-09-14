import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../models/organization_model.dart';
import 'auth_api.dart';

class RegistrationRequest {
  const RegistrationRequest(this.user, this.organization);
  final UserModel user;
  final OrganizationModel? organization;
  String get name => organization?.name ?? user.fullName;
}

class AdminApi {
  AdminApi({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  Stream<List<UserModel>> watchPendingRegistrations() => _db
      .collection('users')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) {
        final users = s.docs
            .map((d) => UserModel.fromMap(d.id, d.data()))
            .where((u) => u.role != UserRole.citizen)
            .toList();
        users.sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          ),
        );
        return users;
      });
  Stream<List<UserModel>> watchPendingRegistrationsByRole(UserRole role) =>
      watchPendingRegistrations().map(
        (users) => users.where((u) => u.role == role).toList(),
      );
  Stream<Map<String, int>> watchOrganizationCounts() => _db
      .collection('organizations')
      .where('status', isEqualTo: 'approved')
      .snapshots()
      .map(
        (snapshot) => {
          for (final type in ['university', 'industry'])
            type: snapshot.docs.where((d) => d.data()['type'] == type).length,
        },
      );
  Future<RegistrationRequest> getRequest(UserModel user) async {
    final id = user.organizationId;
    if (id == null) return RegistrationRequest(user, null);
    final doc = await _db
        .collection('organizations')
        .doc(id)
        .get(const GetOptions(source: Source.server));
    if (!doc.exists) {
      throw const AccountException(
        'The linked organization could not be found.',
      );
    }
    return RegistrationRequest(
      user,
      OrganizationModel.fromMap(doc.id, doc.data()!),
    );
  }

  Future<void> approveRegistration({
    required String uid,
    String? organizationId,
  }) => _transition(uid, 'active', expected: 'pending');
  Future<void> rejectRegistration({
    required String uid,
    required String reason,
    String? organizationId,
  }) {
    if (reason.trim().isEmpty) {
      throw const AccountException('A rejection reason is required.');
    }
    return _transition(
      uid,
      'rejected',
      expected: 'pending',
      reason: reason.trim(),
    );
  }

  Future<void> suspendUser(String uid) =>
      _transition(uid, 'suspended', expected: 'active');
  Future<void> reactivateUser(String uid) =>
      _transition(uid, 'active', expected: 'suspended');
  Future<void> _transition(
    String uid,
    String status, {
    required String expected,
    String? reason,
  }) async {
    final adminUid = _auth.currentUser?.uid;
    if (adminUid == null || adminUid == uid) {
      throw const AccountException(
        'An existing approved administrator must perform this action.',
      );
    }
    await _db.runTransaction((tx) async {
      final admin = await tx.get(_db.collection('users').doc(adminUid));
      if (admin.data()?['role'] != 'admin' ||
          admin.data()?['status'] != 'active') {
        throw const AccountException(
          'Only an approved administrator may manage registrations.',
        );
      }
      final targetRef = _db.collection('users').doc(uid);
      final target = await tx.get(targetRef);
      if (!target.exists) {
        throw const AccountException('This registration no longer exists.');
      }
      final profile = UserModel.fromMap(uid, target.data()!);
      if (profile.status != expected) {
        throw const AccountException(
          'This account status has changed. Refresh and try again.',
        );
      }
      final orgRef = profile.organizationId == null
          ? null
          : _db.collection('organizations').doc(profile.organizationId);
      if (orgRef != null) {
        final org = await tx.get(orgRef);
        if (!org.exists || org.data()?['createdBy'] != uid) {
          throw const AccountException(
            'The organization link is invalid. Contact support.',
          );
        }
      }
      final timestamp = FieldValue.serverTimestamp();
      final audit = <String, dynamic>{
        'updatedAt': timestamp,
        if (status == 'active') ...{
          'approvedBy': adminUid,
          'approvedAt': timestamp,
        },
        if (status == 'rejected') ...{
          'rejectionReason': reason,
          'rejectedBy': adminUid,
          'rejectedAt': timestamp,
        },
        if (status == 'suspended') ...{
          'suspendedBy': adminUid,
          'suspendedAt': timestamp,
        },
      };
      tx.update(targetRef, {'status': status, ...audit});
      if (orgRef != null) {
        tx.update(orgRef, {
          'status': status == 'active' ? 'approved' : status,
          ...audit,
        });
      }
    });
  }
}
