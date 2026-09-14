import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/instance_providers.dart';
import '../models/challenge_model.dart';
import '../models/chat_message_model.dart';
import '../models/industry_interest_model.dart';
import '../models/project_model.dart';
import '../models/user_model.dart';

// ============================================================
// PROVIDERS
// ============================================================

final projectsApiProvider = Provider<ProjectsApi>((ref) {
  return ProjectsApi(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

final allProjectsProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  return ref.watch(projectsApiProvider).watchAll();
});

final universityProjectsProvider = StreamProvider.autoDispose
    .family<List<Project>, String>((ref, organizationId) {
      return ref.watch(projectsApiProvider).watchForUniversity(organizationId);
    });

final projectStreamProvider = StreamProvider.autoDispose
    .family<Project?, String>((ref, projectId) {
      return ref.watch(projectsApiProvider).watch(projectId);
    });

final projectInterestsProvider = StreamProvider.autoDispose
    .family<List<IndustryInterest>, String>((ref, projectId) {
      return ref.watch(projectsApiProvider).watchInterestsForProject(projectId);
    });

final organizationInterestsProvider = StreamProvider.autoDispose
    .family<List<IndustryInterest>, String>((ref, organizationId) {
      return ref
          .watch(projectsApiProvider)
          .watchInterestsByOrganization(organizationId);
    });

final projectMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, projectId) {
      return ref.watch(projectsApiProvider).watchMessages(projectId);
    });

// ============================================================
// PROJECTS API
//
// A project is the university's workspace for an accepted challenge. Every
// change that matters to the citizen is mirrored onto the challenge document
// in the same batch or transaction, so the citizen's live tracking screen
// never disagrees with the project.
// ============================================================

class ProjectsApi {
  ProjectsApi({required FirebaseFirestore firestore, required FirebaseAuth auth})
    : _db = firestore,
      _auth = auth;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _projects =>
      _db.collection('projects');

  CollectionReference<Map<String, dynamic>> get _challenges =>
      _db.collection('challenges');

  CollectionReference<Map<String, dynamic>> get _interests =>
      _db.collection('industryInterests');

  static List<Map<String, dynamic>> _event(String label, {String note = ''}) =>
      [StatusEvent.now(label, note: note).toMap()];

  static List<Project> _parseProjects(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final projects = <Project>[];
    for (final doc in snapshot.docs) {
      try {
        projects.add(Project.fromMap(doc.id, doc.data()));
      } catch (_) {
        // Skip a malformed document rather than break the list.
      }
    }
    projects.sort(
      (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      ),
    );
    return projects;
  }

  static List<IndustryInterest> _parseInterests(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final interests = snapshot.docs
        .map((doc) => IndustryInterest.fromMap(doc.id, doc.data()))
        .toList();
    interests.sort(
      (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      ),
    );
    return interests;
  }

  // ============================================================
  // READ
  // ============================================================

  Stream<List<Project>> watchAll() => _projects.snapshots().map(_parseProjects);

  Stream<List<Project>> watchForUniversity(String organizationId) => _projects
      .where('universityId', isEqualTo: organizationId)
      .snapshots()
      .map(_parseProjects);

  Stream<Project?> watch(String projectId) {
    return _projects.doc(projectId).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return Project.fromMap(doc.id, data);
    });
  }

  Future<Project?> getProject(String projectId) async {
    final doc = await _projects.doc(projectId).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return Project.fromMap(doc.id, data);
  }

  // ============================================================
  // CREATE
  // ============================================================

  /// A university accepts its assigned challenge and opens a workspace.
  Future<Project> createForChallenge({
    required Challenge challenge,
    required String name,
    required String mentor,
    required String universityName,
    List<String> team = const [],
    String description = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Please sign in again.');

    final universityId = challenge.assignedUniversityId ?? '';
    if (universityId.isEmpty) {
      throw Exception('This challenge is not assigned to a university.');
    }
    if (challenge.hasProject) {
      throw Exception('A project already exists for this challenge.');
    }
    if (name.trim().isEmpty) throw Exception('Project name is required.');

    final ref = _projects.doc();
    final milestones = Project.initialMilestones();

    final project = Project(
      id: ref.id,
      name: name.trim(),
      challengeId: challenge.id,
      challengeTitle: challenge.title,
      description: description.trim().isEmpty
          ? challenge.description
          : description.trim(),
      category: challenge.category,
      location: challenge.location,
      universityId: universityId,
      universityName: universityName,
      department: challenge.assignedDepartment ?? '',
      mentor: mentor.trim(),
      team: team.where((m) => m.trim().isNotEmpty).toList(),
      milestones: milestones,
      progress: Project.progressFor(milestones),
      createdBy: user.uid,
    );

    final batch = _db.batch();
    batch.set(ref, {
      ...project.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_challenges.doc(challenge.id), {
      'status': ChallengeStatus.inProgress,
      'projectId': ref.id,
      'progress': project.progress,
      'statusHistory': FieldValue.arrayUnion(
        _event(
          ChallengeStatus.inProgress,
          note: '$universityName started "${project.name}"',
        ),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return project;
  }

  // ============================================================
  // MILESTONES
  // ============================================================

  /// Sign off the stage being worked on and start the next one.
  Future<Project> completeCurrentMilestone(
    String projectId, {
    String note = '',
  }) {
    return _db.runTransaction((tx) async {
      final ref = _projects.doc(projectId);
      final snapshot = await tx.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw Exception('Project not found.');
      }

      final project = Project.fromMap(snapshot.id, data);
      final index = project.milestones.indexWhere((m) => !m.isCompleted);
      if (index == -1) return project;

      final now = DateTime.now();
      final milestones = [
        for (var i = 0; i < project.milestones.length; i++)
          if (i == index)
            project.milestones[i].copyWith(
              status: MilestoneStatus.completed,
              completedAt: now,
              note: note.trim(),
            )
          else if (i == index + 1 && !project.milestones[i].isCompleted)
            project.milestones[i].copyWith(status: MilestoneStatus.inProgress)
          else
            project.milestones[i],
      ];

      final allDone = milestones.every((m) => m.isCompleted);
      final progress = allDone ? 100 : Project.progressFor(milestones);
      final status = allDone ? ProjectStatus.completed : ProjectStatus.active;
      final stageName = project.milestones[index].name;

      tx.update(ref, {
        'milestones': milestones.map((m) => m.toMap()).toList(),
        'progress': progress,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(_challenges.doc(project.challengeId), {
        'progress': progress,
        if (allDone) 'status': ChallengeStatus.solutionDeployed,
        'statusHistory': FieldValue.arrayUnion(
          _event(
            allDone
                ? ChallengeStatus.solutionDeployed
                : 'Milestone completed: $stageName',
            note: note.trim(),
          ),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return project.copyWith(
        milestones: milestones,
        progress: progress,
        status: status,
      );
    });
  }

  /// Close the loop: record the outcome and resolve the citizen's challenge.
  Future<void> reportImpact(
    Project project, {
    required int peopleImpacted,
    required String summary,
  }) async {
    if (peopleImpacted < 0) throw Exception('Enter a valid number of people.');

    final batch = _db.batch();
    batch.update(_projects.doc(project.id), {
      'peopleImpacted': peopleImpacted,
      'impactSummary': summary.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_challenges.doc(project.challengeId), {
      'status': ChallengeStatus.resolved,
      'peopleImpacted': peopleImpacted,
      'progress': 100,
      'statusHistory': FieldValue.arrayUnion(
        _event(
          ChallengeStatus.resolved,
          note: '$peopleImpacted people impacted',
        ),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  // ============================================================
  // INDUSTRY INTEREST
  // ============================================================

  Future<void> expressInterest({
    required Project project,
    required UserModel user,
    required String organizationName,
    required List<String> support,
    required String message,
  }) async {
    if (support.isEmpty) throw Exception('Choose at least one way to help.');

    final organizationId = user.organizationId ?? user.uid;
    final interest = IndustryInterest(
      id: IndustryInterest.docId(project.id, organizationId),
      projectId: project.id,
      projectName: project.name,
      universityName: project.universityName,
      organizationId: organizationId,
      organizationName: organizationName,
      userUid: user.uid,
      userName: user.fullName,
      support: support,
      message: message.trim(),
    );

    await _interests.doc(interest.id).set({
      ...interest.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<IndustryInterest>> watchInterestsForProject(String projectId) =>
      _interests
          .where('projectId', isEqualTo: projectId)
          .snapshots()
          .map(_parseInterests);

  Stream<List<IndustryInterest>> watchInterestsByOrganization(
    String organizationId,
  ) => _interests
      .where('organizationId', isEqualTo: organizationId)
      .snapshots()
      .map(_parseInterests);

  // ============================================================
  // CHAT
  // ============================================================

  Stream<List<ChatMessage>> watchMessages(String projectId) {
    return _projects
        .doc(projectId)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(200)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ChatMessage.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> sendMessage({
    required String projectId,
    required String text,
    required UserModel user,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await _projects
        .doc(projectId)
        .collection('messages')
        .add(
          ChatMessage(
            id: '',
            senderUid: user.uid,
            senderName: user.fullName.isEmpty ? user.email : user.fullName,
            senderRole: user.role.name,
            text: trimmed.length > 2000 ? trimmed.substring(0, 2000) : trimmed,
            createdAt: DateTime.now(),
          ).toMap(),
        );
  }
}
