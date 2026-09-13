// lib/apis/admin_api.dart — replaces the AdminApi stub.

import '../models/challenge_model.dart';
import 'api_client.dart';
import 'challenge_api.dart';

/// One ranked university suggestion, with the reasoning behind the score.
/// Show `reasons` in the UI: an admin overriding a match needs to see why the
/// model picked what it picked.
class UniversityMatch {
  UniversityMatch({
    required this.universityId,
    required this.name,
    required this.department,
    required this.score,
    required this.rank,
    required this.reasons,
    required this.activeProjects,
    required this.capacity,
  });

  final String universityId;
  final String name;
  final String department;
  final double score;
  final int rank;
  final List<String> reasons;
  final int activeProjects;
  final int capacity;

  /// 0-100, for a progress bar or badge.
  int get matchPercent => (score * 100).round();

  static UniversityMatch fromJson(Map<String, dynamic> j) => UniversityMatch(
        universityId: j['university_id'] as String,
        name: j['name'] as String,
        department: j['department'] as String? ?? '',
        score: (j['score'] as num).toDouble(),
        rank: j['rank'] as int? ?? 0,
        reasons: ((j['reasons'] as List?) ?? []).cast<String>(),
        activeProjects: j['active_projects'] as int? ?? 0,
        capacity: j['capacity'] as int? ?? 0,
      );
}

/// One row of the admin review queue: the challenge, its AI analysis, and the
/// ranked universities, all from a single request.
class QueueItem {
  QueueItem(this.challenge, this.ai, this.matches);
  final Challenge challenge;
  final AiSuggestion? ai;
  final List<UniversityMatch> matches;
}

class AdminApi {
  final _api = ApiClient.instance;

  Future<List<QueueItem>> queue() async {
    final rows = await _api.get('/admin/queue') as List;
    return rows.map((row) {
      final r = row as Map<String, dynamic>;
      final c = r['challenge'] as Map<String, dynamic>;
      return QueueItem(
        ChallengeJson.fromJson(c),
        AiSuggestion.fromJson(c['ai'] as Map<String, dynamic>?),
        (r['matches'] as List)
            .map((m) => UniversityMatch.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
    }).toList();
  }

  /// Replaces AppStore.assign(). Confirming the AI pick and overriding it are
  /// the same call; the backend records which one it was.
  Future<Challenge> assign(String challengeId, String universityId, {String? note}) async {
    final data = await _api.post(
      '/admin/challenges/$challengeId/assign',
      body: {'university_id': universityId, if (note != null) 'note': note},
    ) as Map<String, dynamic>;
    return ChallengeJson.fromJson(data);
  }

  /// Pass null to clear a false-positive duplicate flag.
  Future<Challenge> resolveDuplicate(String challengeId, String? duplicateOf) async {
    final data = await _api.post(
      '/admin/challenges/$challengeId/duplicate',
      body: {'duplicate_of': duplicateOf},
    ) as Map<String, dynamic>;
    return ChallengeJson.fromJson(data);
  }

  Future<Challenge> overridePriority(String challengeId, String priority, {String? reason}) async {
    final data = await _api.post(
      '/admin/challenges/$challengeId/priority',
      body: {'priority': priority, if (reason != null) 'reason': reason},
    ) as Map<String, dynamic>;
    return ChallengeJson.fromJson(data);
  }

  Future<Challenge> reject(String challengeId, String reason) async {
    final data = await _api.post(
      '/admin/challenges/$challengeId/reject',
      body: {'reason': reason},
    ) as Map<String, dynamic>;
    return ChallengeJson.fromJson(data);
  }

  /// Analytics dashboard aggregates.
  Future<Map<String, dynamic>> stats() async =>
      await _api.get('/admin/stats') as Map<String, dynamic>;

  Future<List<UniversityMatch>> matchesFor(String challengeId) async {
    final rows = await _api.get('/challenges/$challengeId/matches') as List;
    return rows.map((m) => UniversityMatch.fromJson(m as Map<String, dynamic>)).toList();
  }
}
