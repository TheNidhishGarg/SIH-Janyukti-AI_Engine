import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../apis/projects_api.dart';
import '../../../models/challenge_model.dart';
import '../../../models/project_model.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart';
import '../../citizen/controllers/citizen_controller.dart';
import '../../common/ai_widgets.dart';

// Analytics over live Firestore data.
//
// Chart choices: headline figures are stat tiles, not charts. Every magnitude
// bar uses one hue (the admin blue); the only multi-colour mark is the
// priority mix, which uses the reserved priority colours and always carries
// text labels, so identity never rests on colour alone. Values are printed in
// ink, not in the bar colour.

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dayMonth(DateTime date) => '${date.day} ${_months[date.month - 1]}';

/// Null when there is no denominator, so the UI can say "-" rather than 0%.
int? _percent(int part, int whole) =>
    whole == 0 ? null : (part / whole * 100).round();

String _formatPercent(int? value) => value == null ? '-' : '$value%';

class AnalyticsView extends ConsumerWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengesAsync = ref.watch(challengesProvider);
    final projects =
        ref.watch(allProjectsProvider).asData?.value ?? const <Project>[];

    return PageFrame(
      title: 'Analytics Dashboard',
      color: AppColors.admin,
      child: challengesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load analytics: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (challenges) =>
            _AnalyticsBody(challenges: challenges, projects: projects),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.challenges, required this.projects});

  final List<Challenge> challenges;
  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    final total = challenges.length;

    final resolved = challenges.where((c) {
      final status = c.status.trim().toLowerCase();
      return status == 'resolved' || status == 'solution deployed';
    }).length;

    final impacted = challenges.fold<int>(
      0,
      (sum, c) => sum + (c.peopleImpacted ?? 0),
    );

    final activeProjects = projects.where((p) => !p.isCompleted).length;

    // ---- AI engine -------------------------------------------------------

    final analysed = challenges.where((c) => c.hasAnalysis).toList();

    final averageConfidence = analysed.isEmpty
        ? null
        : (analysed.fold<double>(
                    0,
                    (sum, c) => sum + c.ai!.categoryConfidence,
                  ) /
                  analysed.length *
                  100)
              .round();

    final agreement = _percent(
      analysed.where((c) => c.ai!.categoryMatchesCitizen).length,
      analysed.length,
    );

    // Assignments made from an AI ranking carry a match score.
    final aiRanked = challenges
        .where((c) => c.isAssigned && c.matchScore != null)
        .toList();
    final keptTopPick = _percent(
      aiRanked.where((c) => !c.assignmentWasOverride).length,
      aiRanked.length,
    );

    final possibleDuplicates = challenges
        .where((c) => c.ai?.duplicate != null)
        .length;

    // ---- Weekly volume, last 8 weeks --------------------------------------

    final now = DateTime.now();
    final thisWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final weekStarts = [
      for (var i = 7; i >= 0; i--) thisWeek.subtract(Duration(days: 7 * i)),
    ];
    final weekly = List<int>.filled(weekStarts.length, 0);
    for (final challenge in challenges) {
      for (var i = weekStarts.length - 1; i >= 0; i--) {
        if (!challenge.createdAt.isBefore(weekStarts[i])) {
          weekly[i]++;
          break;
        }
      }
    }

    // ---- Categories, folded to at most seven bars -------------------------

    final categoryCounts = <String, int>{};
    for (final challenge in challenges) {
      final category = challenge.ai?.category ?? challenge.category;
      final key = category.trim().isEmpty ? 'Other' : category;
      categoryCounts[key] = (categoryCounts[key] ?? 0) + 1;
    }
    final sortedCategories = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final categories = <MapEntry<String, int>>[];
    var other = 0;
    for (final entry in sortedCategories) {
      if (entry.key != 'Other' && categories.length < 6) {
        categories.add(entry);
      } else {
        other += entry.value;
      }
    }
    if (other > 0) categories.add(MapEntry('Other', other));

    // ---- Priority mix of open challenges ----------------------------------

    final priorityCounts = <String, int>{'High': 0, 'Medium': 0, 'Low': 0};
    for (final challenge in challenges.where((c) => !c.isClosed)) {
      final priority = challenge.effectivePriority;
      if (priorityCounts.containsKey(priority)) {
        priorityCounts[priority] = priorityCounts[priority]! + 1;
      }
    }

    // ---- Pipeline, in workflow order rather than by size ------------------

    const pipelineOrder = [
      'Submitted',
      'Under Review',
      'Assigned',
      'In Progress',
      'Solution Deployed',
      'Resolved',
      'Duplicate',
      'Rejected',
    ];
    final statusCounts = <String, int>{};
    for (final challenge in challenges) {
      final match = pipelineOrder.firstWhere(
        (status) => status.toLowerCase() == challenge.status.trim().toLowerCase(),
        orElse: () => challenge.status,
      );
      statusCounts[match] = (statusCounts[match] ?? 0) + 1;
    }
    final statuses = [
      for (final status in pipelineOrder)
        if ((statusCounts[status] ?? 0) > 0)
          MapEntry(status, statusCounts[status]!),
    ];

    // ---- Districts, from the AI's location parsing ------------------------

    final districtCounts = <String, int>{};
    for (final challenge in challenges) {
      final district = challenge.ai?.district;
      if (district != null && district.isNotEmpty) {
        districtCounts[district] = (districtCounts[district] ?? 0) + 1;
      }
    }
    final districts = districtCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        section('Overview'),
        Row(
          children: [
            Stat('$total', 'Challenges', AppColors.admin),
            const SizedBox(width: 8),
            Stat('$resolved', 'Resolved', AppColors.admin),
            const SizedBox(width: 8),
            Stat('$impacted', 'People Impacted', AppColors.admin),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Stat('${projects.length}', 'Projects', AppColors.admin),
            const SizedBox(width: 8),
            Stat('$activeProjects', 'Active Projects', AppColors.admin),
            const SizedBox(width: 8),
            Stat('$possibleDuplicates', 'Duplicates Flagged', AppColors.admin),
          ],
        ),

        section('AI Engine'),
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  _MetricTile(
                    value: _formatPercent(_percent(analysed.length, total)),
                    label: 'Analysed',
                    caption: '${analysed.length} of $total challenges',
                  ),
                  _MetricTile(
                    value: _formatPercent(averageConfidence),
                    label: 'Avg confidence',
                    caption: 'Category classification',
                  ),
                ],
              ),
              const Divider(height: 26),
              Row(
                children: [
                  _MetricTile(
                    value: _formatPercent(agreement),
                    label: 'Agrees with citizen',
                    caption: 'Same category chosen',
                  ),
                  _MetricTile(
                    value: _formatPercent(keptTopPick),
                    label: 'Top pick kept',
                    caption: aiRanked.isEmpty
                        ? 'No AI-ranked assignments yet'
                        : 'Of ${aiRanked.length} AI-ranked assignments',
                  ),
                ],
              ),
            ],
          ),
        ),

        section('New Challenges per Week'),
        AppCard(
          child: _WeeklyColumns(
            counts: weekly,
            weekStarts: weekStarts,
            color: AppColors.admin,
          ),
        ),

        section('Categories (AI classified)'),
        AppCard(
          child: _BarList(entries: categories, color: AppColors.admin),
        ),

        section('Open Challenges by Priority'),
        AppCard(child: _PriorityMix(counts: priorityCounts)),

        section('Pipeline'),
        AppCard(child: _BarList(entries: statuses, color: AppColors.admin)),

        if (districts.isNotEmpty) ...[
          section('Top Districts'),
          AppCard(
            child: _BarList(
              entries: districts.take(6).toList(),
              color: AppColors.admin,
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.value,
    required this.label,
    required this.caption,
  });

  final String value;
  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          Text(
            caption,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Horizontal bars: label and value above, a thin single-hue bar below,
/// anchored at the left with a rounded data end.
class _BarList extends StatelessWidget {
  const _BarList({required this.entries, required this.color});

  final List<MapEntry<String, int>> entries;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text(
        'No data yet.',
        style: TextStyle(color: AppColors.muted, fontSize: 12.5),
      );
    }

    final maxValue = entries.fold<int>(0, (m, e) => math.max(m, e.value));
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return Column(
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Semantics(
              label: '${entry.key}: ${entry.value}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${(entry.value / total * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = maxValue == 0
                          ? 0.0
                          : math.max(
                              4.0,
                              constraints.maxWidth * entry.value / maxValue,
                            );
                      return Container(
                        width: width,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Weekly columns. Tap a column to read its exact value; the latest week is
/// selected by default.
class _WeeklyColumns extends StatefulWidget {
  const _WeeklyColumns({
    required this.counts,
    required this.weekStarts,
    required this.color,
  });

  final List<int> counts;
  final List<DateTime> weekStarts;
  final Color color;

  @override
  State<_WeeklyColumns> createState() => _WeeklyColumnsState();
}

class _WeeklyColumnsState extends State<_WeeklyColumns> {
  late int _selected = widget.counts.length - 1;

  static const _chartHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final counts = widget.counts;
    final maxValue = counts.fold<int>(0, (m, v) => math.max(m, v));
    final selectedCount = counts[_selected];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Week of ${_dayMonth(widget.weekStarts[_selected])}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        Text(
          '$selectedCount ${selectedCount == 1 ? 'challenge' : 'challenges'}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < counts.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    label:
                        'Week of ${_dayMonth(widget.weekStarts[i])}: ${counts[i]}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selected = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: maxValue == 0
                                  ? 2
                                  : math.max(
                                      2.0,
                                      _chartHeight * counts[i] / maxValue,
                                    ),
                              decoration: BoxDecoration(
                                color: i == _selected
                                    ? widget.color
                                    : widget.color.withValues(alpha: .40),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.line),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < counts.length; i++)
              Expanded(
                child: Text(
                  // Every other week, always including the latest, so the
                  // labels never collide on a phone.
                  (counts.length - 1 - i).isEven
                      ? _dayMonth(widget.weekStarts[i])
                      : '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One stacked bar of High / Medium / Low with a labelled legend.
class _PriorityMix extends StatelessWidget {
  const _PriorityMix({required this.counts});

  final Map<String, int> counts;

  static const _order = ['High', 'Medium', 'Low'];

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (sum, v) => sum + v);
    if (total == 0) {
      return const Text(
        'No open challenges.',
        style: TextStyle(color: AppColors.muted, fontSize: 12.5),
      );
    }

    final present = [
      for (final priority in _order)
        if ((counts[priority] ?? 0) > 0) priority,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (var i = 0; i < present.length; i++)
                  Expanded(
                    flex: counts[present[i]]!,
                    child: Container(
                      // 2px surface gap between segments.
                      margin: EdgeInsets.only(
                        right: i == present.length - 1 ? 0 : 2,
                      ),
                      color: priorityColor(present[i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final priority in _order)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: priorityColor(priority),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$priority  ${counts[priority] ?? 0}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
