import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/instance_providers.dart';
import '../models/ai_analysis.dart';
import '../models/challenge_model.dart';

// ============================================================
// API PROVIDER
// ============================================================

final challengesApiProvider = Provider<ChallengesApi>((ref) {
  return ChallengesApi(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

// ============================================================
// CHALLENGES API
// Pure Firebase / Firestore layer
// No UI state providers here.
// ============================================================

class ChallengesApi {
  ChallengesApi({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _db = firestore,
       _auth = auth;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _challenges =>
      _db.collection('challenges');

  // ============================================================
  // CURRENT USER
  // ============================================================

  User get currentUser {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not authenticated');
    }

    return user;
  }

  String get currentUserId => currentUser.uid;

  String get currentUserName {
    final user = currentUser;

    final displayName = user.displayName?.trim();

    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user.email?.trim();

    if (email != null && email.isNotEmpty) {
      return email;
    }

    return 'Citizen';
  }

  // ============================================================
  // GENERATE ID
  // ============================================================

  String generateChallengeId() {
    return _challenges.doc().id;
  }

  static List<Map<String, dynamic>> _event(String label, {String note = ''}) =>
      [StatusEvent.now(label, note: note).toMap()];

  static void _require(String value, String message) {
    if (value.trim().isEmpty) throw Exception(message);
  }

  // ============================================================
  // CREATE
  // ============================================================

  Future<Challenge> createChallenge(Challenge challenge) async {
    final user = currentUser;

    final id = challenge.id.isNotEmpty ? challenge.id : generateChallengeId();

    final now = DateTime.now();

    final challengeToSave = challenge.copyWith(
      id: id,
      submittedById: user.uid,
      submittedBy: challenge.submittedBy.trim().isNotEmpty
          ? challenge.submittedBy.trim()
          : currentUserName,
      createdAt: now,
      updatedAt: now,
      // The citizen's app runs the analysis right after this write.
      aiStatus: AiStatus.pending,
      statusHistory: [StatusEvent.now(ChallengeStatus.submitted)],
    );

    final data = challengeToSave.toMap();

    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();

    await _challenges.doc(id).set(data);

    return challengeToSave;
  }

  // ============================================================
  // READ
  // ============================================================

  Future<Challenge?> getChallenge(String challengeId) async {
    _require(challengeId, 'Challenge ID is required');

    final snapshot = await _challenges.doc(challengeId).get();
    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      return null;
    }

    return Challenge.fromMap(id: snapshot.id, map: data);
  }

  Stream<List<Challenge>> watchChallenges() {
    return _challenges
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Challenge.fromMap(id: doc.id, map: doc.data()))
              .toList(),
        );
  }

  Stream<Challenge?> watchChallenge(String challengeId) {
    _require(challengeId, 'Challenge ID is required');

    return _challenges.doc(challengeId).snapshots().map((snapshot) {
      final data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return null;
      }

      return Challenge.fromMap(id: snapshot.id, map: data);
    });
  }

  Stream<List<Challenge>> watchMyChallenges() {
    final userId = currentUserId;

    return _challenges
        .where('submittedById', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final challenges = snapshot.docs
              .map((doc) => Challenge.fromMap(id: doc.id, map: doc.data()))
              .toList();

          // Sort newest first locally.
          challenges.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return challenges;
        });
  }

  /// Challenges assigned to one university organisation.
  Stream<List<Challenge>> watchAssignedTo(String organizationId) {
    _require(organizationId, 'Organization ID is required');

    return _challenges
        .where('assignedUniversityId', isEqualTo: organizationId)
        .snapshots()
        .map((snapshot) {
          final challenges = snapshot.docs
              .map((doc) => Challenge.fromMap(id: doc.id, map: doc.data()))
              .toList();

          challenges.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          return challenges;
        });
  }

  // ============================================================
  // AI ANALYSIS
  // ============================================================

  /// Store the AI engine's findings on the challenge, exactly as returned.
  Future<void> saveAnalysis(String challengeId, AiAnalysis analysis) async {
    _require(challengeId, 'Challenge ID is required');

    await _challenges.doc(challengeId).update({
      'ai': analysis.raw,
      'aiStatus': AiStatus.complete,
      'aiError': FieldValue.delete(),
      'statusHistory': FieldValue.arrayUnion(
        _event(
          'AI analysis complete',
          note: '${analysis.category} · ${analysis.priority} priority',
        ),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAnalysisPending(String challengeId) async {
    _require(challengeId, 'Challenge ID is required');

    await _challenges.doc(challengeId).update({
      'aiStatus': AiStatus.pending,
      'aiError': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAnalysisUnavailable({
    required String challengeId,
    required String reason,
  }) async {
    _require(challengeId, 'Challenge ID is required');

    await _challenges.doc(challengeId).update({
      'aiStatus': AiStatus.unavailable,
      'aiError': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // ADMIN DECISIONS
  // ============================================================

  Future<void> updateStatus({
    required String challengeId,
    required String status,
    String note = '',
  }) async {
    _require(challengeId, 'Challenge ID is required');
    _require(status, 'Status is required');

    await _challenges.doc(challengeId).update({
      'status': status.trim(),
      'statusHistory': FieldValue.arrayUnion(_event(status.trim(), note: note)),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// An admin's priority decision, which from now on outranks the AI's.
  Future<void> updatePriority({
    required String challengeId,
    required String priority,
  }) async {
    _require(challengeId, 'Challenge ID is required');
    _require(priority, 'Priority is required');

    await _challenges.doc(challengeId).update({
      'priority': priority.trim(),
      'priorityOverridden': true,
      'statusHistory': FieldValue.arrayUnion(
        _event('Priority set to ${priority.trim()}'),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCategory({
    required String challengeId,
    required String category,
  }) async {
    _require(challengeId, 'Challenge ID is required');
    _require(category, 'Category is required');

    await _challenges.doc(challengeId).update({
      'category': category.trim(),
      'statusHistory': FieldValue.arrayUnion(
        _event('Category set to ${category.trim()}'),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> assignUniversity({
    required String challengeId,
    required String universityId,
    required String universityName,
    String? department,
    double? matchScore,
    bool wasOverride = false,
  }) async {
    _require(challengeId, 'Challenge ID is required');
    _require(universityId, 'University ID is required');
    _require(universityName, 'University name is required');

    await _challenges.doc(challengeId).update({
      'assignedUniversityId': universityId.trim(),
      'assignedUniversityName': universityName.trim(),
      'assignedDepartment': (department ?? '').trim().isEmpty
          ? FieldValue.delete()
          : department!.trim(),
      'assignedAt': FieldValue.serverTimestamp(),
      'assignedBy': _auth.currentUser?.uid,
      'matchScore': matchScore ?? FieldValue.delete(),
      'assignmentWasOverride': wasOverride,
      'declineReason': FieldValue.delete(),
      'status': ChallengeStatus.assigned,
      'statusHistory': FieldValue.arrayUnion(
        _event(
          'Assigned to ${universityName.trim()}',
          note: (department ?? '').trim(),
        ),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectChallenge({
    required String challengeId,
    required String reason,
  }) async {
    _require(challengeId, 'Challenge ID is required');
    _require(reason, 'A rejection reason is required');

    await _challenges.doc(challengeId).update({
      'status': ChallengeStatus.rejected,
      'rejectionReason': reason.trim(),
      'statusHistory': FieldValue.arrayUnion(
        _event(ChallengeStatus.rejected, note: reason.trim()),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markDuplicate({
    required String challengeId,
    required String originalId,
    required String originalTitle,
  }) async {
    _require(challengeId, 'Challenge ID is required');
    _require(originalId, 'Original challenge ID is required');

    await _challenges.doc(challengeId).update({
      'status': ChallengeStatus.duplicate,
      'duplicateOf': originalId,
      'statusHistory': FieldValue.arrayUnion(
        _event('Merged with an existing report', note: originalTitle),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // UNIVERSITY DECISIONS
  // ============================================================

  /// Hand the challenge back to the admin queue.
  Future<void> declineAssignment({
    required String challengeId,
    required String universityName,
    required String reason,
  }) async {
    _require(challengeId, 'Challenge ID is required');
    _require(reason, 'A reason is required');

    await _challenges.doc(challengeId).update({
      'status': ChallengeStatus.underReview,
      'declineReason': reason.trim(),
      'assignedUniversityId': FieldValue.delete(),
      'assignedUniversityName': FieldValue.delete(),
      'assignedDepartment': FieldValue.delete(),
      'assignedAt': FieldValue.delete(),
      'assignedBy': FieldValue.delete(),
      'matchScore': FieldValue.delete(),
      'assignmentWasOverride': FieldValue.delete(),
      'statusHistory': FieldValue.arrayUnion(
        _event('Declined by $universityName', note: reason.trim()),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
