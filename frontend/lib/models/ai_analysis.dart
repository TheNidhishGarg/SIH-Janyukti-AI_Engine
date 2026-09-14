// Models for the JanYukti AI engine's findings.
//
// AiAnalysis is stored on a challenge document under `ai`, exactly as the
// backend's /ai/analyze endpoint returns it, so it keeps the raw map alongside
// the typed fields. The other classes are request-time results that are shown
// in the UI but not persisted.

double _toDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

int _toInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

String _toStr(Object? value) => value?.toString() ?? '';

String? _toOptionalStr(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

List<String> _toStrings(Object? value) =>
    value is List ? value.map((item) => item.toString()).toList() : const [];

Map<String, dynamic> _toMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<Map<String, dynamic>> _toMaps(Object? value) => value is List
    ? value.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : const [];

class AiDuplicate {
  const AiDuplicate({
    required this.challengeId,
    required this.title,
    required this.score,
    required this.semanticScore,
    required this.lexicalScore,
    required this.sameLocation,
    required this.status,
  });

  final String challengeId;
  final String title;
  final double score;
  final double semanticScore;
  final double lexicalScore;
  final bool sameLocation;
  final String status;

  int get scorePercent => (score * 100).round();

  factory AiDuplicate.fromMap(Map<String, dynamic> map) => AiDuplicate(
    challengeId: _toStr(map['challengeId']),
    title: _toStr(map['title']),
    score: _toDouble(map['score']),
    semanticScore: _toDouble(map['semanticScore']),
    lexicalScore: _toDouble(map['lexicalScore']),
    sameLocation: map['sameLocation'] == true,
    status: _toStr(map['status']),
  );
}

/// A department profile the engine considers a good fit, whether or not the
/// institution has a JanYukti account.
class AiInstitution {
  const AiInstitution({
    required this.profileId,
    required this.institution,
    required this.department,
    required this.city,
    required this.state,
    required this.score,
    required this.scorePercent,
    required this.reasons,
    required this.source,
  });

  final String profileId;
  final String institution;
  final String department;
  final String city;
  final String state;
  final double score;
  final int scorePercent;
  final List<String> reasons;

  /// `openalex` (publication record) or `curated`.
  final String source;

  String get sourceLabel =>
      source == 'openalex' ? 'Publication record' : 'Curated profile';

  factory AiInstitution.fromMap(Map<String, dynamic> map) => AiInstitution(
    profileId: _toStr(map['profileId']),
    institution: _toStr(map['institution']),
    department: _toStr(map['department']),
    city: _toStr(map['city']),
    state: _toStr(map['state']),
    score: _toDouble(map['score']),
    scorePercent: _toInt(map['scorePercent']),
    reasons: _toStrings(map['reasons']),
    source: _toStr(map['source']),
  );
}

class AiAnalysis {
  const AiAnalysis({
    required this.raw,
    required this.version,
    required this.analyzedAt,
    required this.engine,
    required this.category,
    required this.appCategory,
    required this.categoryConfidence,
    required this.needsReview,
    required this.categoryMatchesCitizen,
    required this.tags,
    required this.priority,
    required this.priorityScore,
    required this.scores,
    required this.rationale,
    required this.district,
    required this.state,
    required this.duplicate,
    required this.possibleDuplicates,
    required this.suggestedInstitutions,
  });

  /// Exactly what the backend returned; this is what gets stored in Firestore.
  final Map<String, dynamic> raw;

  final int version;
  final DateTime? analyzedAt;

  /// `heuristic` for the offline engine, `gemini` when the LLM path ran.
  final String engine;

  /// Precise category from the model taxonomy, e.g. "Healthcare & Sanitation".
  final String category;

  /// The same category mapped onto the app's own dropdown options.
  final String appCategory;

  final double categoryConfidence;

  /// Low confidence: an admin should file this by hand.
  final bool needsReview;
  final bool categoryMatchesCitizen;
  final List<String> tags;

  final String priority;
  final double priorityScore;

  /// severity, urgency, reach and vulnerability, each scored 1-5.
  final Map<String, double> scores;
  final String rationale;

  final String? district;
  final String? state;

  final AiDuplicate? duplicate;
  final List<AiDuplicate> possibleDuplicates;
  final List<AiInstitution> suggestedInstitutions;

  static const rubricAxes = ['severity', 'urgency', 'reach', 'vulnerability'];

  int get confidencePercent => (categoryConfidence * 100).round();

  bool get usedLlm => engine == 'gemini';

  factory AiAnalysis.fromMap(Map<String, dynamic> map) {
    final duplicate = map['duplicate'];
    final rawScores = _toMap(map['scores']);

    return AiAnalysis(
      raw: Map<String, dynamic>.from(map),
      version: _toInt(map['version']),
      analyzedAt: DateTime.tryParse(_toStr(map['analyzedAt'])),
      engine: _toStr(map['engine']),
      category: _toStr(map['category']),
      appCategory: _toStr(map['appCategory']),
      categoryConfidence: _toDouble(map['categoryConfidence']),
      needsReview: map['needsReview'] == true,
      categoryMatchesCitizen: map['categoryMatchesCitizen'] == true,
      tags: _toStrings(map['tags']),
      priority: _toStr(map['priority']).isEmpty
          ? 'Medium'
          : _toStr(map['priority']),
      priorityScore: _toDouble(map['priorityScore']),
      scores: {
        for (final entry in rawScores.entries)
          entry.key: _toDouble(entry.value),
      },
      rationale: _toStr(map['rationale']),
      district: _toOptionalStr(map['district']),
      state: _toOptionalStr(map['state']),
      duplicate: duplicate is Map
          ? AiDuplicate.fromMap(Map<String, dynamic>.from(duplicate))
          : null,
      possibleDuplicates: _toMaps(
        map['possibleDuplicates'],
      ).map(AiDuplicate.fromMap).toList(),
      suggestedInstitutions: _toMaps(
        map['suggestedInstitutions'],
      ).map(AiInstitution.fromMap).toList(),
    );
  }
}

/// A registered university organisation ranked for one challenge.
class OrganizationMatch {
  const OrganizationMatch({
    required this.organizationId,
    required this.name,
    required this.city,
    required this.state,
    required this.score,
    required this.scorePercent,
    required this.semanticScore,
    required this.categoryScore,
    required this.capacityScore,
    required this.proximityScore,
    required this.reasons,
    required this.profileLinked,
    required this.profileDepartment,
    required this.profileSource,
    required this.rank,
  });

  final String organizationId;
  final String name;
  final String city;
  final String state;
  final double score;
  final int scorePercent;
  final double semanticScore;
  final double categoryScore;
  final double capacityScore;
  final double proximityScore;
  final List<String> reasons;

  /// False when no expertise profile exists for this institution, so the
  /// ranking rests mostly on location.
  final bool profileLinked;
  final String? profileDepartment;
  final String? profileSource;
  final int rank;

  factory OrganizationMatch.fromMap(Map<String, dynamic> map) =>
      OrganizationMatch(
        organizationId: _toStr(map['organizationId']),
        name: _toStr(map['name']),
        city: _toStr(map['city']),
        state: _toStr(map['state']),
        score: _toDouble(map['score']),
        scorePercent: _toInt(map['scorePercent']),
        semanticScore: _toDouble(map['semanticScore']),
        categoryScore: _toDouble(map['categoryScore']),
        capacityScore: _toDouble(map['capacityScore']),
        proximityScore: _toDouble(map['proximityScore']),
        reasons: _toStrings(map['reasons']),
        profileLinked: map['profileLinked'] == true,
        profileDepartment: _toOptionalStr(map['profileDepartment']),
        profileSource: _toOptionalStr(map['profileSource']),
        rank: _toInt(map['rank']),
      );
}

class MatchResult {
  const MatchResult({
    required this.category,
    required this.registered,
    required this.directory,
  });

  final String category;
  final List<OrganizationMatch> registered;

  /// Strong institutions without a JanYukti account: worth inviting, never
  /// assignable.
  final List<AiInstitution> directory;

  factory MatchResult.fromMap(Map<String, dynamic> map) => MatchResult(
    category: _toStr(map['category']),
    registered: _toMaps(
      map['registered'],
    ).map(OrganizationMatch.fromMap).toList(),
    directory: _toMaps(map['directory']).map(AiInstitution.fromMap).toList(),
  );
}

class DuplicateCheck {
  const DuplicateCheck({
    required this.isDuplicate,
    required this.threshold,
    required this.bestMatch,
    required this.candidates,
  });

  final bool isDuplicate;
  final double threshold;
  final AiDuplicate? bestMatch;
  final List<AiDuplicate> candidates;

  factory DuplicateCheck.fromMap(Map<String, dynamic> map) {
    final best = map['bestMatch'];
    return DuplicateCheck(
      isDuplicate: map['isDuplicate'] == true,
      threshold: _toDouble(map['threshold']),
      bestMatch: best is Map
          ? AiDuplicate.fromMap(Map<String, dynamic>.from(best))
          : null,
      candidates: _toMaps(
        map['candidates'],
      ).map(AiDuplicate.fromMap).toList(),
    );
  }
}
