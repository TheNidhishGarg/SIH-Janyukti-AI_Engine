import 'package:flutter/material.dart';

import '../../models/ai_analysis.dart';
import '../../models/challenge_model.dart';
import '../../theme/app_colors.dart';

// Shared presentation of the AI engine's findings, used by the citizen,
// admin and university screens so the same analysis always reads the same way.

Color priorityColor(String priority) {
  switch (priority.trim().toLowerCase()) {
    case 'high':
      return const Color(0xFFE5484D);
    case 'low':
      return const Color(0xFF12A594);
    default:
      return const Color(0xFFF59E0B);
  }
}

String timeAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return '${time.day}/${time.month}/${time.year}';
}

class PriorityChip extends StatelessWidget {
  const PriorityChip(this.priority, {super.key, this.label});

  final String priority;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label ?? '$priority priority',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.percent, required this.color});

  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$percent% match',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class ScoreBar extends StatelessWidget {
  const ScoreBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    this.trailing,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: AppColors.line,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text(
            trailing ?? value.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Severity, urgency, reach and vulnerability, each out of 5.
class RubricBars extends StatelessWidget {
  const RubricBars({super.key, required this.scores, required this.color});

  final Map<String, double> scores;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final axis in AiAnalysis.rubricAxes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ScoreBar(
              label: axis[0].toUpperCase() + axis.substring(1),
              value: scores[axis] ?? 0,
              max: 5,
              color: color,
              trailing: (scores[axis] ?? 0).toStringAsFixed(1),
            ),
          ),
      ],
    );
  }
}

/// The AI engine's read on one challenge, including the states before a
/// result exists: analysis pending, service unavailable, or never run.
class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    required this.challenge,
    required this.accent,
    this.forAdmin = false,
    this.showRubric = true,
    this.onRetry,
    this.isRetrying = false,
  });

  final Challenge challenge;
  final Color accent;

  /// Admin wording is operational; citizen wording explains what happens next.
  final bool forAdmin;
  final bool showRubric;
  final VoidCallback? onRetry;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    final ai = challenge.ai;

    if (ai == null) {
      if (isRetrying || challenge.aiStatus == AiStatus.pending) {
        return _frame(null, _pending());
      }
      if (challenge.aiStatus == AiStatus.unavailable) {
        return _frame(null, _unavailable());
      }
      if (onRetry == null) return const SizedBox.shrink();
      return _frame(null, _notRun());
    }

    return _frame(ai, _complete(ai));
  }

  Widget _frame(AiAnalysis? ai, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Analysis',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: AppColors.title,
                      ),
                    ),
                    Text(
                      ai == null
                          ? 'Category, priority and similar reports'
                          : 'Analysed ${timeAgo(ai.analyzedAt)} · '
                                '${ai.usedLlm ? 'language model' : 'offline engine'}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (ai != null && isRetrying)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _pending() {
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            forAdmin
                ? 'Analysis in progress.'
                : 'Analysing your report. The category, priority and any '
                      'similar reports will appear here automatically.',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _unavailable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                forAdmin
                    ? (challenge.aiError ??
                          'The AI service could not be reached.')
                    : 'AI analysis is unavailable right now. An administrator '
                          'will review your report manually.',
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
        if (onRetry != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry analysis'),
            ),
          ),
      ],
    );
  }

  Widget _notRun() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'This challenge was submitted before AI analysis was available.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: const Text('Analyse'),
        ),
      ],
    );
  }

  Widget _complete(AiAnalysis ai) {
    final duplicate = ai.duplicate;
    final effective = challenge.effectivePriority;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.category_outlined, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Category',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ai.category,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${ai.confidencePercent}% confident',
              style: TextStyle(
                fontSize: 11.5,
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: ai.categoryConfidence.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.line,
            color: accent,
          ),
        ),
        if (!ai.categoryMatchesCitizen && challenge.category.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${forAdmin ? 'Citizen' : 'You'} selected "${challenge.category}"',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ),
        if (ai.needsReview)
          _note(
            Icons.help_outline_rounded,
            forAdmin
                ? 'Low confidence. File this category by hand.'
                : 'Low confidence. An administrator will confirm the category.',
            Colors.orange,
          ),
        const Divider(height: 26),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Priority',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ),
            PriorityChip(effective),
          ],
        ),
        if (challenge.priorityOverridden && challenge.priority != ai.priority)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'AI assessed ${ai.priority}; an administrator set it to '
              '${challenge.priority}.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ),
        if (ai.rationale.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              ai.rationale,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        if (showRubric && ai.scores.isNotEmpty) ...[
          const SizedBox(height: 12),
          RubricBars(scores: ai.scores, color: priorityColor(ai.priority)),
        ],
        if (duplicate != null)
          _note(
            Icons.content_copy_rounded,
            forAdmin
                ? 'Possible duplicate of "${duplicate.title}" '
                      '(${duplicate.scorePercent}% similar'
                      '${duplicate.sameLocation ? ', same area' : ''}).'
                : 'A similar report already exists: "${duplicate.title}". '
                      'An administrator will check whether it is the same problem.',
            const Color(0xFFB54708),
          ),
        if (onRetry != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: isRetrying ? null : onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(isRetrying ? 'Re-running...' : 'Re-run analysis'),
            ),
          ),
      ],
    );
  }

  Widget _note(IconData icon, String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.title,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
