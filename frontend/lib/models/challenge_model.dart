import 'package:cloud_firestore/cloud_firestore.dart';

import 'ai_analysis.dart';

class ChallengeMedia {
  const ChallengeMedia({
    required this.url,
    required this.publicId,
    required this.type,
    required this.resourceType,
    required this.format,
    required this.bytes,
    this.duration,
  });

  /// photo / video
  final String type;

  final String url;
  final String publicId;
  final String resourceType;
  final String format;
  final int bytes;
  final double? duration;

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'publicId': publicId,
      'type': type,
      'resourceType': resourceType,
      'format': format,
      'bytes': bytes,
      if (duration != null) 'duration': duration,
    };
  }

  factory ChallengeMedia.fromMap(Map<String, dynamic> map) {
    return ChallengeMedia(
      url: map['url']?.toString() ?? '',
      publicId: map['publicId']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      resourceType: map['resourceType']?.toString() ?? '',
      format: map['format']?.toString() ?? '',
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toDouble(),
    );
  }
}

class ChallengeVoiceNote {
  const ChallengeVoiceNote({
    required this.url,
    required this.publicId,
    required this.field,
    required this.transcript,
    required this.resourceType,
    required this.format,
    required this.bytes,
    this.duration,
  });

  /// title / description / additional
  final String field;

  /// Speech-to-text result.
  final String transcript;

  /// Cloudinary URL of original audio.
  final String url;

  final String publicId;
  final String resourceType;
  final String format;
  final int bytes;
  final double? duration;

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'publicId': publicId,
      'field': field,
      'transcript': transcript,
      'resourceType': resourceType,
      'format': format,
      'bytes': bytes,
      if (duration != null) 'duration': duration,
    };
  }

  factory ChallengeVoiceNote.fromMap(Map<String, dynamic> map) {
    return ChallengeVoiceNote(
      url: map['url']?.toString() ?? '',
      publicId: map['publicId']?.toString() ?? '',
      field: map['field']?.toString() ?? '',
      transcript: map['transcript']?.toString() ?? '',
      resourceType: map['resourceType']?.toString() ?? '',
      format: map['format']?.toString() ?? '',
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toDouble(),
    );
  }
}

/// Status values stored on challenge documents.
class ChallengeStatus {
  const ChallengeStatus._();

  static const submitted = 'Submitted';
  static const underReview = 'Under Review';
  static const assigned = 'Assigned';
  static const inProgress = 'In Progress';
  static const solutionDeployed = 'Solution Deployed';
  static const resolved = 'Resolved';
  static const rejected = 'Rejected';
  static const duplicate = 'Duplicate';
}

/// Where the AI analysis of a challenge stands.
class AiStatus {
  const AiStatus._();

  /// Created before the AI service existed, or never sent to it.
  static const none = 'none';
  static const pending = 'pending';
  static const complete = 'complete';

  /// The service could not be reached; see `aiError`.
  static const unavailable = 'unavailable';
}

/// One step in a challenge's journey, recorded so the citizen's timeline can
/// show when each thing actually happened, not just the current status.
class StatusEvent {
  const StatusEvent({required this.label, required this.at, this.note = ''});

  final String label;
  final DateTime at;
  final String note;

  /// Firestore rejects server timestamps inside arrays, so events carry the
  /// client's clock.
  factory StatusEvent.now(String label, {String note = ''}) =>
      StatusEvent(label: label, at: DateTime.now(), note: note);

  Map<String, dynamic> toMap() => {
    'label': label,
    'at': Timestamp.fromDate(at),
    if (note.isNotEmpty) 'note': note,
  };

  factory StatusEvent.fromMap(Map<String, dynamic> map) => StatusEvent(
    label: map['label']?.toString() ?? '',
    at: _optionalDate(map['at']) ?? DateTime.now(),
    note: map['note']?.toString() ?? '',
  );
}

DateTime? _optionalDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

class Challenge {
  Challenge({
    this.id = '',
    required this.title,
    required this.category,
    required this.location,
    required this.description,

    this.additionalInfo = '',

    this.latitude,
    this.longitude,

    this.media = const [],
    this.voiceNotes = const [],

    this.status = 'In Progress',
    this.priority = 'Medium',

    this.submittedBy = '',
    this.submittedById = '',

    DateTime? createdAt,
    DateTime? updatedAt,

    this.ai,
    this.aiStatus = AiStatus.none,
    this.aiError,
    this.priorityOverridden = false,

    this.assignedUniversityId,
    this.assignedUniversityName,
    this.assignedDepartment,
    this.assignedAt,
    this.assignedBy,
    this.matchScore,
    this.assignmentWasOverride = false,

    this.declineReason,
    this.rejectionReason,
    this.duplicateOf,

    this.projectId,
    this.progress = 0,
    this.peopleImpacted,

    this.statusHistory = const [],
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;

  final String title;
  final String category;
  final String location;
  final String description;

  final String additionalInfo;

  final double? latitude;
  final double? longitude;

  final List<ChallengeMedia> media;
  final List<ChallengeVoiceNote> voiceNotes;

  String status;

  /// The stored priority. Until an admin overrides it, prefer
  /// [effectivePriority], which follows the AI assessment.
  final String priority;

  final String submittedBy;
  final String submittedById;

  final DateTime createdAt;
  final DateTime updatedAt;

  // --- AI engine -----------------------------------------------------------

  final AiAnalysis? ai;
  final String aiStatus;
  final String? aiError;

  /// Set once an admin picks a priority by hand; from then on it wins over
  /// the AI's assessment.
  final bool priorityOverridden;

  // --- Assignment ----------------------------------------------------------

  /// Firestore id of the university organisation doing the work.
  final String? assignedUniversityId;
  final String? assignedUniversityName;

  /// The expertise profile the AI matched, e.g. "Water Resources & ...".
  final String? assignedDepartment;
  final DateTime? assignedAt;
  final String? assignedBy;

  /// The AI match score of the chosen university, 0-1.
  final double? matchScore;

  /// True when the admin chose someone other than the AI's top suggestion.
  final bool assignmentWasOverride;

  final String? declineReason;
  final String? rejectionReason;

  /// Id of the original challenge when this one was confirmed a duplicate.
  final String? duplicateOf;

  // --- Delivery ------------------------------------------------------------

  final String? projectId;

  /// 0-100, mirrored from the project's milestones.
  final int progress;
  final int? peopleImpacted;

  final List<StatusEvent> statusHistory;

  // --- Derived -------------------------------------------------------------

  String get effectivePriority =>
      priorityOverridden ? priority : (ai?.priority ?? priority);

  bool get hasAnalysis => ai != null;

  bool get isAssigned => (assignedUniversityId ?? '').isNotEmpty;

  bool get hasProject => (projectId ?? '').isNotEmpty;

  bool get isClosed {
    final value = status.trim().toLowerCase();
    return value == 'resolved' ||
        value == 'rejected' ||
        value == 'duplicate' ||
        value == 'completed';
  }

  String get statusLabel =>
      status == ChallengeStatus.assigned && assignedUniversityName != null
      ? 'Assigned to $assignedUniversityName'
      : status;

  StatusEvent? latestEvent(String labelPrefix) {
    final prefix = labelPrefix.toLowerCase();
    for (final event in statusHistory.reversed) {
      if (event.label.toLowerCase().startsWith(prefix)) return event;
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'category': category,
      'location': location,
      'description': description,

      'additionalInfo': additionalInfo,

      'latitude': latitude,
      'longitude': longitude,

      'media': media.map((x) => x.toMap()).toList(),

      'voiceNotes': voiceNotes.map((x) => x.toMap()).toList(),

      'status': status,
      'priority': priority,

      'submittedBy': submittedBy,
      'submittedById': submittedById,

      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),

      'aiStatus': aiStatus,
      if (ai != null) 'ai': ai!.raw,
      if (aiError != null) 'aiError': aiError,
      'priorityOverridden': priorityOverridden,

      if (assignedUniversityId != null)
        'assignedUniversityId': assignedUniversityId,
      if (assignedUniversityName != null)
        'assignedUniversityName': assignedUniversityName,
      if (assignedDepartment != null) 'assignedDepartment': assignedDepartment,
      if (assignedAt != null) 'assignedAt': Timestamp.fromDate(assignedAt!),
      if (assignedBy != null) 'assignedBy': assignedBy,
      if (matchScore != null) 'matchScore': matchScore,
      if (assignmentWasOverride) 'assignmentWasOverride': true,

      if (declineReason != null) 'declineReason': declineReason,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (duplicateOf != null) 'duplicateOf': duplicateOf,

      if (projectId != null) 'projectId': projectId,
      'progress': progress,
      if (peopleImpacted != null) 'peopleImpacted': peopleImpacted,

      'statusHistory': statusHistory.map((e) => e.toMap()).toList(),
    };
  }

  factory Challenge.fromMap({
    required String id,
    required Map<String, dynamic> map,
  }) {
    DateTime parseDate(dynamic value) => _optionalDate(value) ?? DateTime.now();

    String? optional(String key) {
      final value = map[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    final rawMedia = map['media'];
    final rawVoice = map['voiceNotes'];
    final rawHistory = map['statusHistory'];

    // A malformed analysis must never break the whole challenge stream.
    AiAnalysis? analysis;
    final rawAi = map['ai'];
    if (rawAi is Map) {
      try {
        analysis = AiAnalysis.fromMap(Map<String, dynamic>.from(rawAi));
      } catch (_) {
        analysis = null;
      }
    }

    final history = rawHistory is List
        ? rawHistory
              .whereType<Map>()
              .map((x) => StatusEvent.fromMap(Map<String, dynamic>.from(x)))
              .toList()
        : <StatusEvent>[];
    history.sort((a, b) => a.at.compareTo(b.at));

    final matchScore = map['matchScore'];
    final progress = map['progress'];
    final peopleImpacted = map['peopleImpacted'];

    return Challenge(
      id: id,

      title: map['title']?.toString() ?? '',

      category: map['category']?.toString() ?? '',

      location: map['location']?.toString() ?? '',

      description: map['description']?.toString() ?? '',

      additionalInfo: map['additionalInfo']?.toString() ?? '',

      latitude: (map['latitude'] as num?)?.toDouble(),

      longitude: (map['longitude'] as num?)?.toDouble(),

      media: rawMedia is List
          ? rawMedia
                .whereType<Map>()
                .map(
                  (x) => ChallengeMedia.fromMap(Map<String, dynamic>.from(x)),
                )
                .toList()
          : [],

      voiceNotes: rawVoice is List
          ? rawVoice
                .whereType<Map>()
                .map(
                  (x) =>
                      ChallengeVoiceNote.fromMap(Map<String, dynamic>.from(x)),
                )
                .toList()
          : [],

      status: map['status']?.toString() ?? 'In Progress',

      priority: map['priority']?.toString() ?? 'Medium',

      submittedBy: map['submittedBy']?.toString() ?? '',

      submittedById: map['submittedById']?.toString() ?? '',

      createdAt: parseDate(map['createdAt']),

      updatedAt: parseDate(map['updatedAt']),

      ai: analysis,
      aiStatus:
          optional('aiStatus') ??
          (analysis != null ? AiStatus.complete : AiStatus.none),
      aiError: optional('aiError'),
      priorityOverridden: map['priorityOverridden'] == true,

      assignedUniversityId: optional('assignedUniversityId'),
      assignedUniversityName: optional('assignedUniversityName'),
      assignedDepartment: optional('assignedDepartment'),
      assignedAt: _optionalDate(map['assignedAt']),
      assignedBy: optional('assignedBy'),
      matchScore: matchScore is num ? matchScore.toDouble() : null,
      assignmentWasOverride: map['assignmentWasOverride'] == true,

      declineReason: optional('declineReason'),
      rejectionReason: optional('rejectionReason'),
      duplicateOf: optional('duplicateOf'),

      projectId: optional('projectId'),
      progress: progress is num ? progress.toInt().clamp(0, 100) : 0,
      peopleImpacted: peopleImpacted is num ? peopleImpacted.toInt() : null,

      statusHistory: history,
    );
  }

  Challenge copyWith({
    String? id,
    String? title,
    String? category,
    String? location,
    String? description,
    String? additionalInfo,
    double? latitude,
    double? longitude,
    List<ChallengeMedia>? media,
    List<ChallengeVoiceNote>? voiceNotes,
    String? status,
    String? priority,
    String? submittedBy,
    String? submittedById,
    DateTime? createdAt,
    DateTime? updatedAt,
    AiAnalysis? ai,
    String? aiStatus,
    String? aiError,
    bool? priorityOverridden,
    String? assignedUniversityId,
    String? assignedUniversityName,
    String? assignedDepartment,
    DateTime? assignedAt,
    String? assignedBy,
    double? matchScore,
    bool? assignmentWasOverride,
    String? declineReason,
    String? rejectionReason,
    String? duplicateOf,
    String? projectId,
    int? progress,
    int? peopleImpacted,
    List<StatusEvent>? statusHistory,
  }) {
    return Challenge(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      location: location ?? this.location,
      description: description ?? this.description,
      additionalInfo: additionalInfo ?? this.additionalInfo,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      media: media ?? this.media,
      voiceNotes: voiceNotes ?? this.voiceNotes,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      submittedBy: submittedBy ?? this.submittedBy,
      submittedById: submittedById ?? this.submittedById,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ai: ai ?? this.ai,
      aiStatus: aiStatus ?? this.aiStatus,
      aiError: aiError ?? this.aiError,
      priorityOverridden: priorityOverridden ?? this.priorityOverridden,
      assignedUniversityId: assignedUniversityId ?? this.assignedUniversityId,
      assignedUniversityName:
          assignedUniversityName ?? this.assignedUniversityName,
      assignedDepartment: assignedDepartment ?? this.assignedDepartment,
      assignedAt: assignedAt ?? this.assignedAt,
      assignedBy: assignedBy ?? this.assignedBy,
      matchScore: matchScore ?? this.matchScore,
      assignmentWasOverride:
          assignmentWasOverride ?? this.assignmentWasOverride,
      declineReason: declineReason ?? this.declineReason,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      duplicateOf: duplicateOf ?? this.duplicateOf,
      projectId: projectId ?? this.projectId,
      progress: progress ?? this.progress,
      peopleImpacted: peopleImpacted ?? this.peopleImpacted,
      statusHistory: statusHistory ?? this.statusHistory,
    );
  }
}
