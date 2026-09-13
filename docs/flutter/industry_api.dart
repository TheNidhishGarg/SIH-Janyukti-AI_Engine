// lib/apis/industry_api.dart — replaces the IndustryApi stub.

import '../models/challenge_model.dart';
import 'api_client.dart';
import 'challenge_api.dart';

class IndustryApi {
  final _api = ApiClient.instance;

  /// Challenges worth backing. Defaults to the partner declared focus areas,
  /// so the list is short enough to actually act on.
  Future<List<Challenge>> opportunities({String? category}) async {
    final rows = await _api.get('/industry/opportunities',
        query: {if (category != null) 'category': category}) as List;
    return rows.map((e) => ChallengeJson.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Mirrors the Flutter IndustryInterest model (support list + message).
  Future<Map<String, dynamic>> registerInterest({
    String? challengeId,
    String? projectId,
    required List<String> support,
    String message = '',
    double? fundingAmount,
  }) async =>
      await _api.post('/industry/interests', body: {
        if (challengeId != null) 'challenge_id': challengeId,
        if (projectId != null) 'project_id': projectId,
        'support': support,
        'message': message,
        if (fundingAmount != null) 'funding_amount': fundingAmount,
      }) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> myInterests() async =>
      ((await _api.get('/industry/interests')) as List).cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> stats() async =>
      await _api.get('/industry/stats') as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> profiles() async =>
      ((await _api.get('/industry/profiles')) as List).cast<Map<String, dynamic>>();
}
