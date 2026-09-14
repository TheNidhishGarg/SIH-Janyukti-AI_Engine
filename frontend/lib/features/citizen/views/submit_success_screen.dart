import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routes/app_routes.dart';
import '../../../models/challenge_model.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart';
import '../../common/ai_widgets.dart';
import '../controllers/citizen_controller.dart';

class SubmissionSuccess extends ConsumerWidget {
  const SubmissionSuccess({super.key, required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Follow the saved document so the AI analysis appears here as soon as
    // it lands, without the citizen having to open the tracking screen.
    final live =
        ref.watch(challengeStreamProvider(challenge.id)).asData?.value ??
        challenge;

    return PageFrame(
      title: 'Challenge Submitted',
      color: AppColors.citizen,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 39,
              backgroundColor: AppColors.success,
              child: Icon(Icons.check, size: 48, color: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Thank you!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your challenge has been submitted successfully.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Center(
            child: SelectableText(
              '#${live.id}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: AppColors.muted,
              ),
            ),
          ),
          const SizedBox(height: 24),
          AiInsightCard(
            challenge: live,
            accent: AppColors.citizen,
            showRubric: false,
          ),
          const SizedBox(height: 28),
          RoleButton(
            label: 'Track Challenge',
            color: AppColors.citizen,
            // The track route takes the document id.
            onTap: () =>
                Navigator.pushNamed(context, Routes.track, arguments: live.id),
            icon: Icons.track_changes,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () =>
                Navigator.popUntil(context, ModalRoute.withName(Routes.citizen)),
            child: const Text('Go to Home'),
          ),
        ],
      ),
    );
  }
}
