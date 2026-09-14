import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/instance_providers.dart';
import '../models/organization_model.dart';

// ============================================================
// PROVIDERS
// ============================================================

final organizationsApiProvider = Provider<OrganizationsApi>((ref) {
  return OrganizationsApi(firestore: ref.watch(firebaseFirestoreProvider));
});

/// Approved university organisations: the only valid assignment targets.
final approvedUniversitiesProvider =
    StreamProvider.autoDispose<List<OrganizationModel>>((ref) {
      return ref.watch(organizationsApiProvider).watchApproved('university');
    });

final organizationProvider = StreamProvider.autoDispose
    .family<OrganizationModel?, String>((ref, organizationId) {
      return ref.watch(organizationsApiProvider).watch(organizationId);
    });

// ============================================================
// ORGANIZATIONS API
// ============================================================

class OrganizationsApi {
  OrganizationsApi({required FirebaseFirestore firestore}) : _db = firestore;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _organizations =>
      _db.collection('organizations');

  /// Two equality filters only, so no composite index is needed.
  Stream<List<OrganizationModel>> watchApproved(String type) {
    return _organizations
        .where('type', isEqualTo: type)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .map((snapshot) {
          final organizations = <OrganizationModel>[];
          for (final doc in snapshot.docs) {
            try {
              organizations.add(OrganizationModel.fromMap(doc.id, doc.data()));
            } catch (_) {
              // Skip a malformed registration rather than break the list.
            }
          }
          organizations.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          return organizations;
        });
  }

  Stream<OrganizationModel?> watch(String organizationId) {
    return _organizations.doc(organizationId).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      try {
        return OrganizationModel.fromMap(doc.id, data);
      } catch (_) {
        return null;
      }
    });
  }
}
