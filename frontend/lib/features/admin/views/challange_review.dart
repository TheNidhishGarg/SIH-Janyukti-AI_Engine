import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../apis/ai_api.dart';
import '../../../apis/challenges_api.dart';
import '../../../apis/organizations_api.dart';
import '../../../core/routes/app_routes.dart';
import '../../../models/ai_analysis.dart';
import '../../../models/challenge_model.dart';
import '../../../models/organization_model.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart';
import '../../citizen/controllers/citizen_controller.dart';
import '../../common/ai_widgets.dart';
import '../../common/dialogs.dart';

class ChallengeReview extends ConsumerStatefulWidget {
  const ChallengeReview({super.key, required this.x});

  final Challenge x;

  @override
  ConsumerState<ChallengeReview> createState() => _ChallengeReviewState();
}

class _ChallengeReviewState extends ConsumerState<ChallengeReview> {
  bool _isAnalyzing = false;
  bool _isBusy = false;

  String? _selectedOrganizationId;

  // The AI ranking is fetched once per distinct (challenge, analysis,
  // registered universities) combination rather than on every rebuild.
  String? _matchKey;
  Future<MatchResult>? _matchFuture;

  @override
  Widget build(BuildContext context) {
    // ============================================================
    // REAL-TIME CHALLENGE FROM FIRESTORE
    // ============================================================

    final challengeAsync = ref.watch(challengeStreamProvider(widget.x.id));
    final challenge = challengeAsync.asData?.value ?? widget.x;
    final universitiesAsync = ref.watch(approvedUniversitiesProvider);
    final analysis = challenge.ai;
    final duplicate = analysis?.duplicate;

    return PageFrame(
      title: 'Review Challenge',
      color: AppColors.admin,
      child: RefreshIndicator(
        onRefresh: () async {
          setState(() => _matchKey = null);
          ref.invalidate(challengeStreamProvider(widget.x.id));
          await ref.read(challengeStreamProvider(widget.x.id).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
          children: [
            if (challengeAsync.isLoading)
              const LinearProgressIndicator(minHeight: 2),

            if (challengeAsync.hasError)
              _warningCard('Unable to refresh the latest challenge data.'),

            if (challengeAsync.isLoading || challengeAsync.hasError)
              const SizedBox(height: 12),

            // ======================================================
            // HEADER
            // ======================================================
            _buildChallengeHeader(challenge),

            const SizedBox(height: 20),

            // ======================================================
            // AI ANALYSIS
            // ======================================================
            AiInsightCard(
              challenge: challenge,
              accent: AppColors.admin,
              forAdmin: true,
              isRetrying: _isAnalyzing,
              onRetry: _isAnalyzing ? null : () => _runAnalysis(challenge),
            ),

            if (analysis != null && !challenge.isClosed) ...[
              const SizedBox(height: 12),
              _decisions(challenge, analysis),
            ],

            if (duplicate != null && !challenge.isClosed) ...[
              const SizedBox(height: 12),
              _duplicatePanel(challenge, duplicate),
            ],

            const SizedBox(height: 26),

            // ======================================================
            // DETAILS
            // ======================================================
            _sectionTitle(
              'Challenge Details',
              'Review the citizen submission before assigning it.',
            ),

            const SizedBox(height: 10),

            AppCard(
              child: Column(
                children: [
                  _detailRow(
                    Icons.category_outlined,
                    'Category',
                    challenge.category,
                  ),

                  const Divider(height: 28),

                  _detailRow(
                    Icons.location_on_outlined,
                    'Location',
                    challenge.location,
                  ),

                  if (challenge.latitude != null &&
                      challenge.longitude != null) ...[
                    const Divider(height: 28),

                    _detailRow(
                      Icons.my_location_rounded,
                      'Coordinates',
                      '${challenge.latitude!.toStringAsFixed(5)}, '
                          '${challenge.longitude!.toStringAsFixed(5)}',
                    ),
                  ],

                  const Divider(height: 28),

                  _detailRow(
                    Icons.description_outlined,
                    'Description',
                    challenge.description,
                  ),

                  if (challenge.additionalInfo.trim().isNotEmpty) ...[
                    const Divider(height: 28),

                    _detailRow(
                      Icons.info_outline_rounded,
                      'Additional Information',
                      challenge.additionalInfo,
                    ),
                  ],
                ],
              ),
            ),

            // ======================================================
            // EVIDENCE
            // ======================================================
            if (challenge.media.isNotEmpty ||
                challenge.voiceNotes.isNotEmpty) ...[
              const SizedBox(height: 26),

              _sectionTitle(
                'Submitted Evidence',
                'Review the original photo, video and voice evidence.',
              ),

              const SizedBox(height: 12),

              for (final media in challenge.media) ...[
                _ChallengeMediaCard(media: media),

                const SizedBox(height: 12),
              ],

              for (final voice in challenge.voiceNotes) ...[
                _ChallengeVoiceCard(voice: voice),

                const SizedBox(height: 12),
              ],
            ],

            const SizedBox(height: 26),

            // ======================================================
            // SUBMISSION INFORMATION
            // ======================================================
            _sectionTitle('Submission', 'Citizen and workflow information.'),

            const SizedBox(height: 10),

            AppCard(
              child: Column(
                children: [
                  _detailRow(
                    Icons.person_outline_rounded,
                    'Submitted By',
                    challenge.submittedBy.trim().isEmpty
                        ? 'Citizen'
                        : challenge.submittedBy,
                  ),

                  const Divider(height: 28),

                  _detailRow(
                    Icons.calendar_today_outlined,
                    'Submitted At',
                    _formatDate(challenge.createdAt),
                  ),

                  const Divider(height: 28),

                  _detailRow(
                    Icons.flag_outlined,
                    'Priority',
                    challenge.priorityOverridden
                        ? '${challenge.priority} (set by admin)'
                        : challenge.effectivePriority,
                  ),

                  if (challenge.declineReason != null) ...[
                    const Divider(height: 28),

                    _detailRow(
                      Icons.undo_rounded,
                      'Previously Declined',
                      challenge.declineReason!,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ======================================================
            // UNIVERSITY ASSIGNMENT
            // ======================================================
            _sectionTitle(
              'Assign University',
              'Registered universities ranked by the AI engine on expertise, '
                  'focus area, capacity and location.',
            ),

            const SizedBox(height: 12),

            _assignmentSection(challenge, universitiesAsync),

            if (!challenge.isClosed) ...[
              const SizedBox(height: 14),

              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isBusy ? null : () => _reject(challenge),
                  icon: const Icon(
                    Icons.block_rounded,
                    color: Colors.redAccent,
                  ),
                  label: const Text(
                    'Reject Challenge',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // AI
  // ============================================================

  Future<void> _runAnalysis(Challenge challenge) async {
    setState(() => _isAnalyzing = true);

    final result = await ref
        .read(citizenControllerProvider.notifier)
        .analyzeChallenge(challenge, markPending: true);

    if (!mounted) return;

    setState(() {
      _isAnalyzing = false;
      _matchKey = null;
    });

    if (result == null) {
      _snack(
        'AI analysis is unavailable. Check that the backend is running.',
        error: true,
      );
    }
  }

  Widget _decisions(Challenge challenge, AiAnalysis analysis) {
    final suggestedCategory = analysis.appCategory;
    final canApplyCategory =
        suggestedCategory.isNotEmpty &&
        suggestedCategory != 'Other' &&
        suggestedCategory != challenge.category;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your decision',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 3),
          const Text(
            'Confirm or override what the AI assessed.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final priority in const ['High', 'Medium', 'Low'])
                ChoiceChip(
                  label: Text(priority),
                  selected: challenge.effectivePriority == priority,
                  selectedColor: priorityColor(
                    priority,
                  ).withValues(alpha: .18),
                  labelStyle: TextStyle(
                    color: challenge.effectivePriority == priority
                        ? priorityColor(priority)
                        : AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: _isBusy
                      ? null
                      : (_) => _setPriority(challenge, priority),
                ),
            ],
          ),
          if (canApplyCategory) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isBusy
                  ? null
                  : () => _applyCategory(challenge, suggestedCategory),
              icon: const Icon(Icons.category_outlined),
              label: Text('Use AI category: $suggestedCategory'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _duplicatePanel(Challenge challenge, AiDuplicate duplicate) {
    const amber = Color(0xFFB54708);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: amber.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.content_copy_rounded, color: amber, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Possible duplicate',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '"${duplicate.title}"',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            '${duplicate.scorePercent}% similar'
            '${duplicate.sameLocation ? ' · same area' : ''}'
            ' · ${duplicate.status}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _isBusy
                    ? null
                    : () => _openChallenge(duplicate.challengeId),
                child: const Text('Open original'),
              ),
              FilledButton(
                onPressed: _isBusy
                    ? null
                    : () => _confirmDuplicate(challenge, duplicate),
                style: FilledButton.styleFrom(backgroundColor: amber),
                child: const Text('Mark as duplicate'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ASSIGNMENT
  // ============================================================

  Widget _assignmentSection(
    Challenge challenge,
    AsyncValue<List<OrganizationModel>> universitiesAsync,
  ) {
    if (challenge.isClosed) {
      return _infoCard(
        Icons.lock_outline_rounded,
        'This challenge is ${challenge.status.toLowerCase()}, so it cannot be assigned.',
      );
    }

    if (challenge.hasProject) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _currentAssignment(challenge),
          const SizedBox(height: 10),
          _infoCard(
            Icons.engineering_outlined,
            'The university has started a project, so the assignment is '
            'locked. Follow it under Project Monitoring.',
          ),
        ],
      );
    }

    return universitiesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _warningCard(
        'Could not load registered universities: ${_message(error)}',
      ),
      data: (universities) {
        final key = [
          challenge.id,
          challenge.ai?.analyzedAt?.toIso8601String() ?? '',
          ...universities.map((u) => u.id),
        ].join('|');

        if (key != _matchKey) {
          _matchKey = key;
          _matchFuture = ref
              .read(aiApiProvider)
              .matchOrganizations(
                challenge: challenge,
                organizations: universities,
              );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (challenge.isAssigned) ...[
              _currentAssignment(challenge),
              const SizedBox(height: 14),
            ],
            FutureBuilder<MatchResult>(
              future: _matchFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _rankingLoading();
                }
                if (snapshot.hasError) {
                  return _manualAssignment(
                    challenge,
                    universities,
                    _message(snapshot.error!),
                  );
                }
                return _rankedAssignment(challenge, snapshot.data!);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _rankingLoading() {
    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.admin,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Ranking registered universities with the AI engine...',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankedAssignment(Challenge challenge, MatchResult result) {
    final ranked = result.registered;

    if (ranked.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _infoCard(
            Icons.school_outlined,
            'No approved university accounts yet. Approve university '
            'registrations before assigning challenges.',
          ),
          if (result.directory.isNotEmpty) ...[
            const SizedBox(height: 22),
            _directory(result.directory),
          ],
        ],
      );
    }

    final selectedId =
        _selectedOrganizationId ?? challenge.assignedUniversityId;
    var selected = ranked.first;
    for (final match in ranked) {
      if (match.organizationId == selectedId) selected = match;
    }
    final alreadyAssigned =
        challenge.assignedUniversityId == selected.organizationId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final match in ranked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MatchTile(
              match: match,
              selected: match.organizationId == selected.organizationId,
              onTap: _isBusy
                  ? null
                  : () => setState(
                      () => _selectedOrganizationId = match.organizationId,
                    ),
            ),
          ),

        if (selected.rank != 1 && !alreadyAssigned)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              "You are overriding the AI's top pick. This is recorded with the assignment.",
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),

        _assignButton(
          label: alreadyAssigned
              ? 'Already assigned here'
              : challenge.isAssigned
              ? 'Reassign to ${selected.name}'
              : 'Assign to ${selected.name}',
          onPressed: alreadyAssigned
              ? null
              : () => _assign(
                  challenge,
                  organizationId: selected.organizationId,
                  name: selected.name,
                  department: selected.profileDepartment,
                  score: selected.score,
                  wasOverride: selected.rank != 1,
                ),
        ),

        if (result.directory.isNotEmpty) ...[
          const SizedBox(height: 22),
          _directory(result.directory),
        ],
      ],
    );
  }

  /// When the AI service is down, assignment still works - just unranked.
  Widget _manualAssignment(
    Challenge challenge,
    List<OrganizationModel> universities,
    String reason,
  ) {
    if (universities.isEmpty) {
      return _infoCard(
        Icons.school_outlined,
        'AI ranking is unavailable and no approved university accounts exist yet.',
      );
    }

    final selectedId =
        _selectedOrganizationId ?? challenge.assignedUniversityId;
    var selected = universities.first;
    for (final university in universities) {
      if (university.id == selectedId) selected = university;
    }
    final alreadyAssigned = challenge.assignedUniversityId == selected.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _warningCard(
          'AI ranking unavailable: $reason You can still assign manually.',
        ),
        const SizedBox(height: 12),
        for (final university in universities)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OrganizationOptionTile(
              title: university.name,
              subtitle: [
                university.city,
                university.state,
              ].where((part) => part.isNotEmpty).join(', '),
              selected: university.id == selected.id,
              onTap: _isBusy
                  ? null
                  : () => setState(
                      () => _selectedOrganizationId = university.id,
                    ),
            ),
          ),
        const SizedBox(height: 4),
        _assignButton(
          label: alreadyAssigned
              ? 'Already assigned here'
              : 'Assign to ${selected.name}',
          onPressed: alreadyAssigned
              ? null
              : () => _assign(
                  challenge,
                  organizationId: selected.id,
                  name: selected.name,
                ),
        ),
      ],
    );
  }

  Widget _currentAssignment(Challenge challenge) {
    final department = challenge.assignedDepartment;
    final score = challenge.matchScore;
    final details = [
      if (score != null) '${(score * 100).round()}% AI match',
      if (challenge.assignmentWasOverride) 'admin override',
      if (challenge.assignedAt != null) timeAgo(challenge.assignedAt),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.admin.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.assignment_turned_in_rounded,
            color: AppColors.admin,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigned to ${challenge.assignedUniversityName ?? 'a university'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (department != null)
                  Text(
                    department,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _directory(List<AiInstitution> directory) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Recommended, not yet on JanYukti',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 3),
        const Text(
          'Strong fits without an account. Invite them to register so future '
          'challenges can be assigned to them.',
          style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 10),
        for (final institution in directory)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: 12,
              child: Row(
                children: [
                  const Icon(Icons.school_outlined, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          institution.institution,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${institution.department} · ${institution.sourceLabel}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ScoreBadge(
                    percent: institution.scorePercent,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _assignButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: _isBusy ? null : onPressed,
        icon: _isBusy
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.assignment_ind_rounded),
        label: Text(
          _isBusy ? 'Saving...' : label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.admin,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ACTIONS
  // ============================================================

  Future<void> _runBusy(
    Future<void> Function() action, {
    required String success,
    bool popAfter = false,
  }) async {
    setState(() => _isBusy = true);
    try {
      await action();
      if (!mounted) return;
      _snack(success);
      if (popAfter) Navigator.pop(context);
    } catch (error) {
      if (mounted) _snack(_message(error), error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _assign(
    Challenge challenge, {
    required String organizationId,
    required String name,
    String? department,
    double? score,
    bool wasOverride = false,
  }) {
    return _runBusy(
      () => ref
          .read(citizenControllerProvider.notifier)
          .assignUniversity(
            challengeId: challenge.id,
            universityId: organizationId,
            universityName: name,
            department: department,
            matchScore: score,
            wasOverride: wasOverride,
          ),
      success: 'Challenge assigned to $name',
      popAfter: true,
    );
  }

  Future<void> _setPriority(Challenge challenge, String priority) async {
    if (challenge.priorityOverridden && challenge.priority == priority) return;
    await _runBusy(
      () => ref
          .read(citizenControllerProvider.notifier)
          .updatePriority(challengeId: challenge.id, priority: priority),
      success: 'Priority set to $priority',
    );
  }

  Future<void> _applyCategory(Challenge challenge, String category) {
    return _runBusy(
      () => ref
          .read(citizenControllerProvider.notifier)
          .updateCategory(challengeId: challenge.id, category: category),
      success: 'Category set to $category',
    );
  }

  Future<void> _confirmDuplicate(
    Challenge challenge,
    AiDuplicate duplicate,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: 'Mark as duplicate?',
      message:
          'This report will be closed and linked to "${duplicate.title}", '
          'which continues as the original.',
      confirmLabel: 'Mark duplicate',
      confirmColor: const Color(0xFFB54708),
    );
    if (!confirmed || !mounted) return;

    await _runBusy(
      () => ref
          .read(citizenControllerProvider.notifier)
          .markDuplicate(
            challengeId: challenge.id,
            originalId: duplicate.challengeId,
            originalTitle: duplicate.title,
          ),
      success: 'Marked as a duplicate',
      popAfter: true,
    );
  }

  Future<void> _reject(Challenge challenge) async {
    final reason = await askForText(
      context,
      title: 'Reject challenge',
      message: 'The reason is recorded on the challenge.',
      hint: 'Why is this not being taken forward?',
      confirmLabel: 'Reject',
      confirmColor: Colors.redAccent,
    );
    if (reason == null || !mounted) return;

    await _runBusy(
      () => ref
          .read(citizenControllerProvider.notifier)
          .rejectChallenge(challengeId: challenge.id, reason: reason),
      success: 'Challenge rejected',
      popAfter: true,
    );
  }

  Future<void> _openChallenge(String challengeId) async {
    try {
      final original = await ref
          .read(challengesApiProvider)
          .getChallenge(challengeId);
      if (!mounted) return;
      if (original == null) {
        _snack('The original report no longer exists.', error: true);
        return;
      }
      Navigator.pushNamed(context, Routes.review, arguments: original);
    } catch (error) {
      if (mounted) _snack(_message(error), error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Colors.redAccent : null,
        ),
      );
  }

  static String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildChallengeHeader(Challenge challenge) {
    final statusColor = _statusColor(challenge.status);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.darkPurpleTextGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.admin.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${challenge.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.white100,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),

                    const SizedBox(width: 6),

                    Text(
                      challenge.statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            challenge.title,
            style: const TextStyle(
              fontSize: 21,
              height: 1.25,
              fontWeight: FontWeight.w900,
              color: AppColors.white100,
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: AppColors.white100,
                size: 18,
              ),

              const SizedBox(width: 6),

              Expanded(
                child: Text(
                  challenge.location,
                  style: const TextStyle(
                    color: AppColors.white100,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  challenge.category,
                  style: const TextStyle(
                    color: AppColors.white100,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: PriorityChip(challenge.effectivePriority),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: AppColors.admin.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 20, color: AppColors.admin),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.title,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,

                  fontWeight: FontWeight.normal,
                  color: AppColors.title,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.title,
          ),
        ),

        const SizedBox(height: 3),

        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _infoCard(IconData icon, String message) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warningCard(String message) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, color: Colors.orange, size: 18),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    final value = status.trim().toLowerCase();

    if (value.contains('resolved') ||
        value.contains('completed') ||
        value.contains('deployed')) {
      return Colors.green;
    }

    if (value.contains('review')) {
      return Colors.orange;
    }

    if (value.contains('assigned')) {
      return AppColors.admin;
    }

    if (value.contains('progress')) {
      return Colors.blue;
    }

    if (value.contains('reject') || value.contains('duplicate')) {
      return Colors.redAccent;
    }

    return const Color(0xFF667085);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/${date.year} $hour:$minute';
  }
}

// ============================================================
// RANKED UNIVERSITY
// ============================================================

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.match,
    required this.selected,
    required this.onTap,
  });

  final OrganizationMatch match;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final department = match.profileDepartment;
    final place = [
      match.city,
      match.state,
    ].where((part) => part.isNotEmpty).join(', ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.admin.withValues(alpha: .05)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.admin : const Color(0xFFE0E6EF),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.admin : AppColors.muted,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        match.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                      if (department != null)
                        Text(
                          department,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      if (place.isNotEmpty)
                        Text(
                          place,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ScoreBadge(
                      percent: match.scorePercent,
                      color: AppColors.admin,
                    ),
                    if (match.rank == 1)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Top AI pick',
                          style: TextStyle(
                            color: AppColors.admin,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ScoreBar(
              label: 'Expertise',
              value: match.semanticScore,
              max: 1,
              color: AppColors.admin,
              trailing: '${(match.semanticScore * 100).round()}%',
            ),
            const SizedBox(height: 6),
            ScoreBar(
              label: 'Focus area',
              value: match.categoryScore,
              max: 1,
              color: AppColors.admin,
              trailing: '${(match.categoryScore * 100).round()}%',
            ),
            const SizedBox(height: 6),
            ScoreBar(
              label: 'Capacity',
              value: match.capacityScore,
              max: 1,
              color: AppColors.admin,
              trailing: '${(match.capacityScore * 100).round()}%',
            ),
            const SizedBox(height: 6),
            ScoreBar(
              label: 'Proximity',
              value: match.proximityScore,
              max: 1,
              color: AppColors.admin,
              trailing: '${(match.proximityScore * 100).round()}%',
            ),
            if (match.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final reason in match.reasons.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.admin,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reason,
                          style: const TextStyle(fontSize: 12, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrganizationOptionTile extends StatelessWidget {
  const _OrganizationOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.admin : const Color(0xFFE0E6EF),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.admin : AppColors.muted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MEDIA
// ============================================================

class _ChallengeMediaCard extends StatelessWidget {
  const _ChallengeMediaCard({required this.media});

  final ChallengeMedia media;

  @override
  Widget build(BuildContext context) {
    final resourceType = media.resourceType.toLowerCase();

    final type = media.type.toLowerCase();

    final isImage =
        resourceType == 'image' || type == 'photo' || type == 'image';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isImage)
            Image.network(
              media.url,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) {
                  return child;
                }

                return const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox(
                  height: 180,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 42,
                      color: AppColors.muted,
                    ),
                  ),
                );
              },
            )
          else
            _ReviewVideoPlayer(url: media.url),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  isImage ? Icons.image_outlined : Icons.videocam_outlined,
                  color: AppColors.admin,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    isImage ? 'Photo Evidence' : 'Video Evidence',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),

                if (media.format.isNotEmpty)
                  Text(
                    media.format.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// VIDEO
// ============================================================

class _ReviewVideoPlayer extends StatefulWidget {
  const _ReviewVideoPlayer({required this.url});

  final String url;

  @override
  State<_ReviewVideoPlayer> createState() => _ReviewVideoPlayerState();
}

class _ReviewVideoPlayerState extends State<_ReviewVideoPlayer> {
  late final VideoPlayerController _controller;

  bool _initialized = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();

      if (!mounted) return;

      setState(() {
        _initialized = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Unable to load video',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }

    if (!_initialized) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller),

              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  });
                },
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ],
          ),
        ),

        VideoProgressIndicator(
          _controller,
          allowScrubbing: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ],
    );
  }
}

// ============================================================
// VOICE
// ============================================================

class _ChallengeVoiceCard extends StatefulWidget {
  const _ChallengeVoiceCard({required this.voice});

  final ChallengeVoiceNote voice;

  @override
  State<_ChallengeVoiceCard> createState() => _ChallengeVoiceCardState();
}

class _ChallengeVoiceCardState extends State<_ChallengeVoiceCard> {
  final AudioPlayer _player = AudioPlayer();

  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _isPlaying = false;
      });
    });
  }

  Future<void> _toggleAudio() async {
    try {
      if (_isPlaying) {
        await _player.pause();

        if (!mounted) return;

        setState(() {
          _isPlaying = false;
        });

        return;
      }

      await _player.play(UrlSource(widget.voice.url));

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggleAudio,
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.admin.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: AppColors.admin,
                size: 28,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _voiceTitle(widget.voice.field),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),

                if (widget.voice.transcript.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),

                  Text(
                    widget.voice.transcript,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),
                ],

                if (widget.voice.duration != null) ...[
                  const SizedBox(height: 5),

                  Text(
                    '${widget.voice.duration!.toStringAsFixed(1)} sec',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _voiceTitle(String field) {
    switch (field) {
      case 'title':
        return 'Title Voice Note';

      case 'description':
        return 'Description Voice Note';

      case 'additional':
        return 'Additional Information Voice Note';

      default:
        return 'Voice Note';
    }
  }
}
