
class ProjectApi {
  final _api = ApiClient.instance;

  /// Replaces AppStore.accept() + createProject(): the university takes the
  /// challenge on and the workspace is created in one call.
  Future<ProjectItem> acceptChallenge({
    required String challengeId,
    required String name,
    String mentor = '',
    String description = '',
    List<String> milestones = const [],
  }) async {
    final data = await _api.post('/projects', body: {
      'challenge_id': challengeId,
      'name': name,
      'mentor': mentor,
      'description': description,
      'milestones': milestones,
    }) as Map<String, dynamic>;
    return ProjectItem.fromJson(data);
  }

  Future<List<ProjectItem>> list({bool mine = true, String? universityId}) async {
    final data = await _api.get('/projects', query: {
      'mine': mine,
      if (universityId != null) 'university_id': universityId,
    }) as Map<String, dynamic>;
    return (data['items'] as List)
        .map((e) => ProjectItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ProjectItem> get(String id) async =>
      ProjectItem.fromJson(await _api.get('/projects/$id') as Map<String, dynamic>);

  /// Replaces AppStore.advance(): the university reports a stage complete.
  /// Progress is recomputed server-side, so use the returned project.
  Future<ProjectItem> submitMilestone(
    String projectId,
    String milestoneId, {
    String? evidenceUrl,
    String? note,
  }) async {
    final data = await _api.post(
      '/projects/$projectId/milestones/$milestoneId/submit',
      body: {'evidence_url': evidenceUrl, 'note': note},
    ) as Map<String, dynamic>;
    return ProjectItem.fromJson(data);
  }

  /// Admin approves a submitted milestone, or sends it back for rework.
  Future<ProjectItem> reviewMilestone(
    String projectId,
    String milestoneId, {
    required bool approved,
    String? note,
  }) async {
    final data = await _api.post(
      '/projects/$projectId/milestones/$milestoneId/review',
      body: {'approved': approved, 'note': note},
    ) as Map<String, dynamic>;
    return ProjectItem.fromJson(data);
  }

  Future<ProjectItem> reportImpact(
    String projectId, {
    required int peopleImpacted,
    String summary = '',
    Map<String, dynamic> metrics = const {},
  }) async {
    final data = await _api.post('/projects/$projectId/impact', body: {
      'people_impacted': peopleImpacted,
      'summary': summary,
      'metrics': metrics,
    }) as Map<String, dynamic>;
    return ProjectItem.fromJson(data);
  }

  /// Pass the last message id as `after` to poll only for new messages.
  Future<List<ChatMessage>> chat(String projectId, {String? after}) async {
    final rows = await _api.get('/projects/$projectId/chat',
        query: {if (after != null) 'after': after}) as List;
    return rows.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList();
  }

  /// Replaces AppStore.send().
  Future<ChatMessage> send(String projectId, String body) async {
    final data = await _api.post('/projects/$projectId/chat', body: {'body': body})
        as Map<String, dynamic>;
    return ChatMessage.fromJson(data);
  }
}
