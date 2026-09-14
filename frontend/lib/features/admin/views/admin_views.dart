import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../apis/ai_api.dart';
import '../../../core/routes/app_routes.dart';
import '../../../models/challenge_model.dart';
import '../providers/admin_providers.dart';
import '../../../theme/app_colors.dart';
import '../../auth/services/auth_session.dart';
import '../../citizen/controllers/citizen_controller.dart';
import '../widgets/challange_card.dart';
import '../widgets/matric_card.dart';
import '../widgets/section_header.dart';
import '../widgets/status_card.dart';
import 'registration_approvals_view.dart';

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ============================================================
    // REAL-TIME FIRESTORE CHALLENGES
    // ============================================================

    final challengesAsync = ref.watch(challengesProvider);

    // Keep the AI duplicate index in step with Firestore. This is the one
    // screen that already streams every challenge.
    ref.listen<AsyncValue<List<Challenge>>>(challengesProvider, (previous, next) {
      final challenges = next.asData?.value;
      if (challenges != null) {
        AiIndexSync.maybeSync(ref.read(aiApiProvider), challenges);
      }
    });

    final organizationCounts = ref
        .watch(organizationCountsProvider)
        .asData
        ?.value;
    final pendingRegistrations = ref
        .watch(pendingRegistrationsProvider)
        .asData
        ?.value;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FE),
      body: SafeArea(
        child: Column(
          children: [
            // ======================================================
            // HEADER
            // ======================================================
            _DashboardHeader(onLogout: () => AuthSession.signOut(context)),

            // ======================================================
            // BODY
            // ======================================================
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(challengesProvider);

                  await ref.read(challengesProvider.future);
                },
                child: challengesAsync.when(
                  loading: () {
                    return const _DashboardLoading();
                  },

                  error: (error, stackTrace) {
                    return _DashboardError(
                      message: error.toString().replaceFirst('Exception: ', ''),
                      onRetry: () {
                        ref.invalidate(challengesProvider);
                      },
                    );
                  },

                  data: (challenges) {
                    return _DashboardContent(
                      challenges: challenges,
                      universityCount: organizationCounts?['university'] ?? 0,
                      industryCount: organizationCounts?['industry'] ?? 0,
                      pendingRequestCount: pendingRegistrations?.length ?? 0,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HEADER
// ============================================================

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Dashboard',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF101B42),
                    letterSpacing: -0.7,
                  ),
                ),

                SizedBox(height: 4),

                Text(
                  'Monitor challenges, registrations and platform activity',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF667085)),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.admin.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'A',
                style: TextStyle(
                  color: AppColors.admin,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ),

          const SizedBox(width: 2),

          IconButton(
            tooltip: 'Logout',
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, color: Color(0xFF344054)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DASHBOARD CONTENT
// ============================================================

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.challenges,
    required this.universityCount,
    required this.industryCount,
    required this.pendingRequestCount,
  });

  final List<Challenge> challenges;
  final int universityCount;
  final int industryCount;
  final int pendingRequestCount;

  @override
  Widget build(BuildContext context) {
    // ============================================================
    // REAL DERIVED COUNTS
    // ============================================================

    final totalChallenges = challenges.length;

    final submittedCount = _countStatus(challenges, const ['submitted']);

    final underReviewCount = _countStatus(challenges, const ['under review']);

    final assignedCount = challenges.where((challenge) {
      final status = challenge.status.trim().toLowerCase();

      return status.startsWith('assigned');
    }).length;

    final inProgressCount = _countStatus(challenges, const ['in progress']);

    final resolvedCount = _countStatus(challenges, const [
      'resolved',
      'completed',
      'solution deployed',
      'deployed',
    ]);

    // Provider/API already returns newest first.
    final recentChallenges = challenges.take(5).toList();

    // ============================================================
    // AI ENGINE
    // ============================================================

    final openChallenges = challenges.where((c) => !c.isClosed).toList();

    final analysedCount = challenges.where((c) => c.hasAnalysis).length;

    final highPriorityCount = openChallenges
        .where((c) => c.effectivePriority == 'High')
        .length;

    final duplicateCount = openChallenges
        .where((c) => c.ai?.duplicate != null)
        .length;

    final needsReviewCount = openChallenges
        .where((c) => c.ai?.needsReview ?? false)
        .length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 34),
      children: [
        // ========================================================
        // OVERVIEW
        // ========================================================
        Row(
          children: [
            const Expanded(
              child: Text(
                'Overview',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF101B42),
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE4E9F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: Color(0xFF667085),
                  ),

                  const SizedBox(width: 6),

                  Text(
                    _dashboardDate(DateTime.now()),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF667085),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ========================================================
        // TOP METRICS
        // ========================================================
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.75,
          children: [
            MetricCard(
              count: totalChallenges,
              label: 'Challenges',
              icon: Icons.description_rounded,
              color: AppColors.admin,
            ),

            MetricCard(
              count: universityCount,
              label: 'Universities',
              icon: Icons.school_rounded,
              color: Color(0xFF8A4DE8),
            ),

            MetricCard(
              count: industryCount,
              label: 'Industries',
              icon: Icons.apartment_rounded,
              color: Color(0xFF16A779),
            ),

            MetricCard(
              count: pendingRequestCount,
              label: 'Pending Requests',
              icon: Icons.groups_rounded,
              color: Color(0xFFF59E0B),
              highlighted: true,
            ),
          ],
        ),

        const SizedBox(height: 20),

        _AiEngineSummary(
          total: challenges.length,
          analysed: analysedCount,
          highPriority: highPriorityCount,
          possibleDuplicates: duplicateCount,
          needsReview: needsReviewCount,
        ),

        const SizedBox(height: 28),

        // ========================================================
        // CHALLENGE PIPELINE
        // ========================================================
        SectionHeader(
          title: 'Challenge Pipeline',
          onViewAll: () {
            Navigator.pushNamed(context, Routes.analytics);
          },
        ),

        const SizedBox(height: 12),

        _PipelineSummary(
          submitted: submittedCount,
          review: underReviewCount,
          assigned: assignedCount,
          progress: inProgressCount,
          resolved: resolvedCount,
        ),

        const SizedBox(height: 28),

        // ========================================================
        // STATUS CARDS
        // ========================================================
        const Text(
          'Challenge Status',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101B42),
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: StatusCard(
                count: underReviewCount,
                label: 'Under Review',
                icon: Icons.schedule_rounded,
                color: const Color(0xFFF59E0B),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: StatusCard(
                count: assignedCount,
                label: 'Assigned',
                icon: Icons.group_rounded,
                color: AppColors.admin,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: StatusCard(
                count: resolvedCount,
                label: 'Resolved',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF10A875),
              ),
            ),
          ],
        ),

        const SizedBox(height: 30),

        // ========================================================
        // REGISTRATION REQUESTS
        // ========================================================
        SectionHeader(
          title: 'Registration Requests',
          onViewAll: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RegistrationApprovalsView(),
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        const RegistrationApprovalsPreview(),

        const SizedBox(height: 30),

        // ========================================================
        // RECENT CHALLENGES
        // ========================================================
        SectionHeader(
          title: 'Recent Challenges',
          onViewAll: () {
            Navigator.pushNamed(context, Routes.analytics);
          },
        ),

        const SizedBox(height: 12),

        if (recentChallenges.isEmpty)
          const _EmptyChallenges()
        else
          ...recentChallenges.map((challenge) {
            final display = _challengeDisplay(challenge);

            return Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: ChallengeCard(
                challenge: challenge,

                // REAL Firestore status
                status: challenge.statusLabel,

                statusColor: display.statusColor,

                // Based on REAL category
                icon: display.icon,

                iconColor: display.iconColor,

                onTap: () {
                  Navigator.pushNamed(
                    context,
                    Routes.review,
                    arguments: challenge,
                  );
                },
              ),
            );
          }),

        const SizedBox(height: 12),

        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, Routes.monitoring);
            },
            icon: const Icon(Icons.engineering_outlined, color: AppColors.admin),
            label: const Text(
              'Project Monitoring',
              style: TextStyle(
                color: AppColors.admin,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: BorderSide(color: AppColors.admin.withValues(alpha: .28)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ========================================================
        // ANALYTICS
        // ========================================================
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, Routes.analytics);
            },
            icon: Icon(Icons.analytics_outlined, color: AppColors.admin),
            label: Text(
              'Open Analytics Dashboard',
              style: TextStyle(
                color: AppColors.admin,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: BorderSide(color: AppColors.admin.withOpacity(.28)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // COUNT STATUS
  // ============================================================

  static int _countStatus(List<Challenge> challenges, List<String> statuses) {
    return challenges.where((challenge) {
      final status = challenge.status.trim().toLowerCase();

      return statuses.contains(status);
    }).length;
  }

  // ============================================================
  // CATEGORY + STATUS UI
  // ============================================================

  static _ChallengeDisplay _challengeDisplay(Challenge challenge) {
    final category = challenge.category.trim().toLowerCase();

    final status = challenge.status.trim().toLowerCase();

    IconData icon;
    Color iconColor;

    if (category.contains('water')) {
      icon = Icons.water_drop_rounded;
      iconColor = const Color(0xFF16A6E5);
    } else if (category.contains('waste')) {
      icon = Icons.delete_outline_rounded;
      iconColor = const Color(0xFF16A779);
    } else if (category.contains('agriculture')) {
      icon = Icons.eco_rounded;
      iconColor = const Color(0xFF18A558);
    } else if (category.contains('health')) {
      icon = Icons.local_hospital_rounded;
      iconColor = const Color(0xFFE8505B);
    } else if (category.contains('education')) {
      icon = Icons.school_rounded;
      iconColor = const Color(0xFF8A4DE8);
    } else if (category.contains('infrastructure')) {
      icon = Icons.construction_rounded;
      iconColor = const Color(0xFFF59E0B);
    } else {
      icon = Icons.campaign_rounded;
      iconColor = AppColors.admin;
    }

    Color statusColor;

    if (status.contains('resolved') ||
        status.contains('completed') ||
        status.contains('deployed')) {
      statusColor = const Color(0xFF10A875);
    } else if (status.contains('review')) {
      statusColor = const Color(0xFFF59E0B);
    } else if (status.contains('assigned')) {
      statusColor = AppColors.admin;
    } else if (status.contains('progress')) {
      statusColor = const Color(0xFF3478F6);
    } else if (status.contains('reject')) {
      statusColor = Colors.redAccent;
    } else {
      statusColor = const Color(0xFF667085);
    }

    return _ChallengeDisplay(
      icon: icon,
      iconColor: iconColor,
      statusColor: statusColor,
    );
  }

  static String _dashboardDate(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${days[date.weekday - 1]}, '
        '${date.day} '
        '${months[date.month - 1]} '
        '${date.year}';
  }
}

// ============================================================
// PIPELINE
// ============================================================

class _PipelineSummary extends StatelessWidget {
  const _PipelineSummary({
    required this.submitted,
    required this.review,
    required this.assigned,
    required this.progress,
    required this.resolved,
  });

  final int submitted;
  final int review;
  final int assigned;
  final int progress;
  final int resolved;

  @override
  Widget build(BuildContext context) {
    final total = submitted + review + assigned + progress + resolved;

    if (total == 0) {
      return const _EmptyPipeline();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9F0)),
      ),
      child: Column(
        children: [
          _PipelineRow(
            label: 'Submitted',
            count: submitted,
            total: total,
            color: const Color(0xFF667085),
          ),

          const SizedBox(height: 13),

          _PipelineRow(
            label: 'Under Review',
            count: review,
            total: total,
            color: const Color(0xFFF59E0B),
          ),

          const SizedBox(height: 13),

          _PipelineRow(
            label: 'Assigned',
            count: assigned,
            total: total,
            color: AppColors.admin,
          ),

          const SizedBox(height: 13),

          _PipelineRow(
            label: 'In Progress',
            count: progress,
            total: total,
            color: const Color(0xFF3478F6),
          ),

          const SizedBox(height: 13),

          _PipelineRow(
            label: 'Resolved',
            count: resolved,
            total: total,
            color: const Color(0xFF10A875),
          ),
        ],
      ),
    );
  }
}

class _PipelineRow extends StatelessWidget {
  const _PipelineRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : count / total;

    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),

            const SizedBox(width: 8),

            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF344054),
                ),
              ),
            ),

            Text(
              '$count',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),

        const SizedBox(height: 7),

        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: const Color(0xFFF1F3F6),
            color: color,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// EMPTY STATES
// ============================================================

class _EmptyChallenges extends StatelessWidget {
  const _EmptyChallenges();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9F0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 38, color: Color(0xFF98A2B3)),

          SizedBox(height: 10),

          Text(
            'No challenges yet',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),

          SizedBox(height: 4),

          Text(
            'New citizen challenges will appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
          ),
        ],
      ),
    );
  }
}

class _EmptyPipeline extends StatelessWidget {
  const _EmptyPipeline();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9F0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.hourglass_empty_rounded, color: Color(0xFF98A2B3)),

          SizedBox(width: 12),

          Expanded(
            child: Text(
              'Challenge pipeline will appear once citizens start submitting challenges.',
              style: TextStyle(color: Color(0xFF667085), fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LOADING
// ============================================================

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: const [
        SizedBox(height: 140),

        Center(child: CircularProgressIndicator()),

        SizedBox(height: 16),

        Center(
          child: Text(
            'Loading dashboard...',
            style: TextStyle(color: Color(0xFF667085)),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ERROR
// ============================================================

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 100),

        const Icon(
          Icons.cloud_off_outlined,
          size: 50,
          color: Color(0xFF98A2B3),
        ),

        const SizedBox(height: 16),

        const Text(
          'Unable to load dashboard',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),

        const SizedBox(height: 7),

        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF667085)),
        ),

        const SizedBox(height: 18),

        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// DISPLAY CONFIG
// ============================================================

class _AiEngineSummary extends StatelessWidget {
  const _AiEngineSummary({
    required this.total,
    required this.analysed,
    required this.highPriority,
    required this.possibleDuplicates,
    required this.needsReview,
  });

  final int total;
  final int analysed;
  final int highPriority;
  final int possibleDuplicates;
  final int needsReview;

  @override
  Widget build(BuildContext context) {
    final coverage = total == 0 ? 0 : (analysed / total * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.darkPurpleTextGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AI Engine',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '$coverage% analysed',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('$highPriority', 'High priority'),
              _stat('$possibleDuplicates', 'Possible duplicates'),
              _stat('$needsReview', 'Need manual filing'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
        ),
      ],
    ),
  );
}

class _ChallengeDisplay {
  const _ChallengeDisplay({
    required this.icon,
    required this.iconColor,
    required this.statusColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color statusColor;
}
