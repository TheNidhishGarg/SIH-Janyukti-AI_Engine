// lib/apis/challenge_api.dart — replaces the ChallengeApi stub.

import '../models/challenge_model.dart';
import 'api_client.dart';

/// The backend sends `status_label`, which is the exact string the UI already
/// expects ("Assigned to BIT Mesra"), so existing widgets need no change.
extension ChallengeJson on Challenge {
  static Challenge fromJson(Map<String, dynamic> j) => Challenge(
        id: j['id'] as String,
        title: j['title'] as String,
        category: j['category'] as String,
        location: j['location'] as String? ?? '',
        description: j['description'] as String,
        status: j['status_label'] as String? ?? j['status'] as String,
        priority: j['priority'] as String? ?? 'Medium',
        submittedBy: j['submitted_by'] as String? ?? '',
      );
}

/// The AI engine read on a challenge, for the admin review screen.
class AiSuggestion {
  AiSuggestion({
    required this.category,
    required this.confidence,
    required this.priority,
    required this.rationale,
    required this.scores,
    this.duplicateOf,
  });

  final String category;
  final double confidence;
  final String priority;
  final String rationale;
  final Map<String, dynamic> scores;
  final String? duplicateOf;

  static AiSuggestion? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : AiSuggestion(
          category: j['category'] as String? ?? '',
          confidence: (j['category_confidence'] as num?)?.toDouble() ?? 0,
          priority: j['priority'] as String? ?? '',
          rationale: j['rationale'] as String? ?? '',
          scores: (j['scores'] as Map?)?.cast<String, dynamic>() ?? const {},
          duplicateOf: j['duplicate_of'] as String?,
        );
}

class TimelineEvent {
  TimelineEvent(this.label, this.detail, this.at);
  final String label;
  final String? detail;
  final DateTime at;

  static TimelineEvent fromJson(Map<String, dynamic> j) => TimelineEvent(
        j['label'] as String,
        j['detail'] as String?,
        DateTime.parse(j['created_at'] as String),
      );
}

class ChallengeDetail {
  ChallengeDetail(this.challenge, this.ai, this.timeline);
  final Challenge challenge;
  final AiSuggestion? ai;
  final List<TimelineEvent> timeline;
}

class ChallengeApi {
  final _api = ApiClient.instance;

  /// Replaces AppStore.addChallenge(). Pass analyzeSync: true to get the AI
  /// result back in the same response (slower, but ideal for a live demo).
  Future<ChallengeDetail> submit({
    required String title,
    required String description,
    required String category,
    required String location,
    String? district,
    String? state,
    int peopleImpacted = 0,
    List<Map<String, dynamic>> attachments = const [],
    bool analyzeSync = false,
  }) async {
    final data = await _api.post(
      '/challenges',
      query: {'analyze_sync': analyzeSync},
      body: {
        'title': title,
        'description': description,
        'category': category,
        'location': location,
        if (district != null) 'district': district,
        if (state != null) 'state': state,
        'people_impacted': peopleImpacted,
        'attachments': attachments,
      },
    ) as Map<String, dynamic>;
    return _detail(data);
  }

  Future<List<Challenge>> list({
    bool mine = false,
    String? status,
    String? category,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _api.get('/challenges', query: {
      'mine': mine,
      if (status != null) 'status': status,
      if (category != null) 'category': category,
      if (search != null) 'search': search,
      'page': page,
      'page_size': pageSize,
    }) as Map<String, dynamic>;

    return (data['items'] as List)
        .map((e) => ChallengeJson.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChallengeDetail> get(String id) async =>
      _detail(await _api.get('/challenges/$id') as Map<String, dynamic>);

  /// Live duplicate check while the citizen is still typing. Call it when the
  /// description field loses focus, so a duplicate is prevented rather than
  /// cleaned up afterwards.
  Future<Map<String, dynamic>?> checkDuplicate({
    required String title,
    required String description,
    String category = '',
    String location = '',
  }) async {
    final data = await _api.post('/ml/duplicates', body: {
      'title': title,
      'description': description,
      'category': category,
      'location': location,
    }) as Map<String, dynamic>;
    return data['is_duplicate'] == true
        ? data['best_match'] as Map<String, dynamic>
        : null;
  }

  /// Populates the category dropdown from the server taxonomy.
  Future<List<String>> categories() async =>
      (await _api.get('/ml/categories') as List).cast<String>();

  Future<Map<String, dynamic>> myStats() async =>
      await _api.get('/me/stats') as Map<String, dynamic>;

  ChallengeDetail _detail(Map<String, dynamic> j) => ChallengeDetail(
        ChallengeJson.fromJson(j),
        AiSuggestion.fromJson(j['ai'] as Map<String, dynamic>?),
        ((j['timeline'] as List?) ?? [])
            .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
