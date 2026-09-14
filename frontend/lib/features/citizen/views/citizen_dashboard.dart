import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/common/error_text.dart';
import '../../../core/routes/app_routes.dart';
import '../../../models/challenge_model.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/loader.dart';
import '../../../widgets/ui.dart';
import '../../auth/providers/user_provider.dart';
import '../../auth/services/auth_session.dart';
import '../controllers/citizen_controller.dart';
import '../widgets/challange_card.dart';

class CitizenDashboard extends ConsumerWidget {
  const CitizenDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    // Watch challenge data only once.
    final challengesAsync = ref.watch(myChallengesProvider);

    // Existing data if available.
    // While loading/error, this becomes an empty list.
    final challenges = challengesAsync.asData?.value ?? const <Challenge>[];

    // ============================================================
    // DERIVED DASHBOARD DATA
    // ============================================================

    final totalChallenges = challenges.length;

    final inProgressCount = challenges.where((challenge) {
      final status = challenge.status.trim().toLowerCase();

      return status == 'in progress';
    }).length;

    final resolvedCount = challenges.where((challenge) {
      final status = challenge.status.trim().toLowerCase();

      return status == 'resolved' || status == 'completed';
    }).length;

    // Backend already returns createdAt descending,
    // so taking first 3 gives latest challenges.
    final recentChallenges = challenges.take(3).toList();

    return PageFrame(
      title: 'janYukti',
      color: AppColors.citizen,
      actions: [
        const Icon(Icons.notifications_none),

        const SizedBox(width: 12),

        IconButton(
          tooltip: 'Logout',
          onPressed: () => AuthSession.signOut(context),
          icon: const Icon(Icons.logout_outlined),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myChallengesProvider);

          // Wait until refreshed provider returns data/error.
          await ref.read(myChallengesProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            // ======================================================
            // GREETING
            // ======================================================
            Text(
              'Hello${user == null || user.fullName.trim().isEmpty ? '' : ', ${user.fullName.trim()}'} 👋',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 3),

            const Text(
              'What would you like to do?',
              style: TextStyle(color: AppColors.muted),
            ),

            const SizedBox(height: 18),

            // ======================================================
            // REPORT CHALLENGE
            // ======================================================
            RoleButton(
              label: 'Report a Challenge',
              color: AppColors.citizen,
              icon: Icons.add_circle_outline,
              onTap: () {
                Navigator.pushNamed(context, Routes.submit);
              },
            ),

            const SizedBox(height: 10),

            // ======================================================
            // MY CHALLENGES
            // ======================================================
            OutlinedButton.icon(
              onPressed: challenges.isEmpty
                  ? null
                  : () {
                      Navigator.pushNamed(
                        context,
                        Routes.track,
                        arguments: challenges.first.id,
                      );
                    },
              icon: const Icon(Icons.track_changes),
              label: Text(
                challenges.isEmpty
                    ? 'No Challenges Yet'
                    : 'view Latest Challenge',
              ),
            ),

            const SizedBox(height: 24),

            // ======================================================
            // IMPACT
            // ======================================================
            Text(
              'Your Impact',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.title,
              ),
            ),

            const SizedBox(height: 10),

            if (challengesAsync.isLoading && challenges.isEmpty)
              const SizedBox(
                height: 74,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Row(
                children: [
                  Stat('$totalChallenges', 'Challenges', AppColors.citizen),

                  const SizedBox(width: 8),

                  Stat('$inProgressCount', 'In Progress', AppColors.citizen),

                  const SizedBox(width: 8),

                  Stat('$resolvedCount', 'Resolved', AppColors.citizen),
                ],
              ),

            const SizedBox(height: 26),

            // ======================================================
            // RECENT CHALLENGES HEADER
            // ======================================================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Challenges',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.title,
                  ),
                ),

                if (challenges.length > 3)
                  TextButton(
                    onPressed: () {
                      // If later you create a dedicated
                      // "My Challenges" listing route,
                      // navigate there from here.
                    },
                    child: const Text('View all'),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // ======================================================
            // CHALLENGE DATA
            // ======================================================
            challengesAsync.when(
              data: (_) {
                if (recentChallenges.isEmpty) {
                  return _EmptyChallenges(
                    onReport: () {
                      Navigator.pushNamed(context, Routes.submit);
                    },
                  );
                }

                return Column(
                  children: [
                    for (final challenge in recentChallenges) ...[
                      ChallengeCard(
                        challenge,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            Routes.track,
                            arguments: challenge.id,
                          );
                        },
                      ),

                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },

              error: (error, stackTrace) {
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ErrorText(error: error.toString()),
                );
              },

              loading: () {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Loader(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// EMPTY STATE
// ============================================================

class _EmptyChallenges extends StatelessWidget {
  const _EmptyChallenges({required this.onReport});

  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.citizen.withOpacity(.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.citizen.withOpacity(.10)),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.citizen.withOpacity(.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.campaign_outlined,
              color: AppColors.citizen,
              size: 28,
            ),
          ),

          const SizedBox(height: 13),

          const Text(
            'No challenges yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 5),

          const Text(
            'Report a local issue and track its progress here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 15),

          TextButton.icon(
            onPressed: onReport,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Report Challenge'),
          ),
        ],
      ),
    );
  }
}
