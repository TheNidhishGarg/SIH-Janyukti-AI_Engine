import 'package:cloud_firestore/cloud_firestore.dart';

/// Status values for a project milestone.
class MilestoneStatus {
  const MilestoneStatus._();

  static const pending = 'Pending';
  static const inProgress = 'In Progress';
  static const completed = 'Completed';
}

/// Status values for a project.
class ProjectStatus {
  const ProjectStatus._();

  static const active = 'Active';
  static const completed = 'Completed';
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

class ProjectMilestone {
  const ProjectMilestone({
    required this.name,
    this.status = MilestoneStatus.pending,
    this.completedAt,
    this.note = '',
  });

  final String name;
  final String status;
  final DateTime? completedAt;
  final String note;

  bool get isCompleted => status == MilestoneStatus.completed;
  bool get isActive => status == MilestoneStatus.inProgress;

  Map<String, dynamic> toMap() => {
    'name': name,
    'status': status,
    if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
    if (note.isNotEmpty) 'note': note,
  };

  factory ProjectMilestone.fromMap(Map<String, dynamic> map) =>
      ProjectMilestone(
        name: map['name']?.toString() ?? '',
        status: map['status']?.toString() ?? MilestoneStatus.pending,
        completedAt: _date(map['completedAt']),
        note: map['note']?.toString() ?? '',
      );

  ProjectMilestone copyWith({
    String? status,
    DateTime? completedAt,
    String? note,
  }) => ProjectMilestone(
    name: name,
    status: status ?? this.status,
    completedAt: completedAt ?? this.completedAt,
    note: note ?? this.note,
  );
}

/// The workspace a university creates when it accepts a challenge.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.challengeId,
    required this.universityId,
    this.challengeTitle = '',
    this.description = '',
    this.category = '',
    this.location = '',
    this.universityName = '',
    this.department = '',
    this.mentor = '',
    this.team = const [],
    this.milestones = const [],
    this.progress = 0,
    this.status = ProjectStatus.active,
    this.createdBy = '',
    this.createdAt,
    this.updatedAt,
    this.peopleImpacted,
    this.impactSummary = '',
  });

  static const defaultMilestones = [
    'Problem Analysis',
    'Research & Feasibility',
    'Prototype Development',
    'Field Testing',
    'Deployment',
  ];

  final String id;
  final String name;
  final String challengeId;
  final String challengeTitle;
  final String description;
  final String category;
  final String location;

  /// Firestore id of the university organisation.
  final String universityId;
  final String universityName;
  final String department;

  final String mentor;
  final List<String> team;
  final List<ProjectMilestone> milestones;

  /// 0-100, derived from the milestones.
  final int progress;
  final String status;

  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final int? peopleImpacted;
  final String impactSummary;

  /// Kept for screens written against the earlier mock model.
  String get university => universityName;

  bool get isCompleted => status == ProjectStatus.completed;

  bool get hasImpactReport => peopleImpacted != null;

  int get completedCount => milestones.where((m) => m.isCompleted).length;

  /// Index of the milestone being worked on; the last one once all are done.
  int get activeMilestone {
    if (milestones.isEmpty) return 0;
    final index = milestones.indexWhere((m) => !m.isCompleted);
    return index == -1 ? milestones.length - 1 : index;
  }

  ProjectMilestone? get currentMilestone {
    final index = milestones.indexWhere((m) => !m.isCompleted);
    return index == -1 ? null : milestones[index];
  }

  List<String> get milestoneNames => milestones.map((m) => m.name).toList();

  /// Work under way counts as half a milestone, so the bar moves as soon as a
  /// team starts rather than only when a stage is signed off.
  static int progressFor(List<ProjectMilestone> milestones) {
    if (milestones.isEmpty) return 0;
    final completed = milestones.where((m) => m.isCompleted).length;
    final active = milestones.any((m) => m.isActive) ? 0.5 : 0.0;
    return (((completed + active) / milestones.length) * 100).round().clamp(
      0,
      100,
    );
  }

  static List<ProjectMilestone> initialMilestones([
    List<String> names = defaultMilestones,
  ]) => [
    for (var i = 0; i < names.length; i++)
      ProjectMilestone(
        name: names[i],
        status: i == 0 ? MilestoneStatus.inProgress : MilestoneStatus.pending,
      ),
  ];

  Map<String, dynamic> toMap() => {
    'name': name,
    'challengeId': challengeId,
    'challengeTitle': challengeTitle,
    'description': description,
    'category': category,
    'location': location,
    'universityId': universityId,
    'universityName': universityName,
    'department': department,
    'mentor': mentor,
    'team': team,
    'milestones': milestones.map((m) => m.toMap()).toList(),
    'progress': progress,
    'status': status,
    'createdBy': createdBy,
    if (peopleImpacted != null) 'peopleImpacted': peopleImpacted,
    if (impactSummary.isNotEmpty) 'impactSummary': impactSummary,
  };

  factory Project.fromMap(String id, Map<String, dynamic> map) {
    final rawMilestones = map['milestones'];
    final rawTeam = map['team'];
    final progress = map['progress'];
    final people = map['peopleImpacted'];

    return Project(
      id: id,
      name: map['name']?.toString() ?? '',
      challengeId: map['challengeId']?.toString() ?? '',
      challengeTitle: map['challengeTitle']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      location: map['location']?.toString() ?? '',
      universityId: map['universityId']?.toString() ?? '',
      universityName: map['universityName']?.toString() ?? '',
      department: map['department']?.toString() ?? '',
      mentor: map['mentor']?.toString() ?? '',
      team: rawTeam is List
          ? rawTeam.map((x) => x.toString()).toList()
          : const [],
      milestones: rawMilestones is List
          ? rawMilestones
                .whereType<Map>()
                .map((x) => ProjectMilestone.fromMap(Map<String, dynamic>.from(x)))
                .toList()
          : const [],
      progress: progress is num ? progress.toInt().clamp(0, 100) : 0,
      status: map['status']?.toString() ?? ProjectStatus.active,
      createdBy: map['createdBy']?.toString() ?? '',
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      peopleImpacted: people is num ? people.toInt() : null,
      impactSummary: map['impactSummary']?.toString() ?? '',
    );
  }

  Project copyWith({
    List<ProjectMilestone>? milestones,
    int? progress,
    String? status,
    int? peopleImpacted,
    String? impactSummary,
  }) => Project(
    id: id,
    name: name,
    challengeId: challengeId,
    universityId: universityId,
    challengeTitle: challengeTitle,
    description: description,
    category: category,
    location: location,
    universityName: universityName,
    department: department,
    mentor: mentor,
    team: team,
    milestones: milestones ?? this.milestones,
    progress: progress ?? this.progress,
    status: status ?? this.status,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: updatedAt,
    peopleImpacted: peopleImpacted ?? this.peopleImpacted,
    impactSummary: impactSummary ?? this.impactSummary,
  );
}
