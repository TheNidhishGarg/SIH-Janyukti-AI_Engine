// lib/apis/university_api.dart — new file; the university-side inbox.

import '../models/challenge_model.dart';
import 'api_client.dart';
import 'challenge_api.dart';

class UniversityApi {
  final _api = ApiClient.instance;

  /// Public directory — use it to populate the picker on the signup screen.
  Future<List<Map<String, dynamic>>> list({String? category, String? search}) async =>
      ((await _api.get('/universities', query: {
        if (category != null) 'category': category,
        if (search != null) 'search': search,
      })) as List)
          .cast<Map<String, dynamic>>();

  /// Challenges assigned to this university and awaiting an accept/decline.
  Future<List<Challenge>> inbox(String universityId) async {
    final rows = await _api.get('/universities/$universityId/inbox') as List;
    return rows.map((e) => ChallengeJson.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Declining returns the challenge to the admin queue rather than stalling it.
  Future<Challenge> decline(String universityId, String challengeId, String reason) async {
    final data = await _api.post(
      '/universities/$universityId/decline/$challengeId',
      body: {'reason': reason},
    ) as Map<String, dynamic>;
    return ChallengeJson.fromJson(data);
  }

  Future<Map<String, dynamic>> stats(String universityId) async =>
      await _api.get('/universities/$universityId/stats') as Map<String, dynamic>;
}
