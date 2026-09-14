import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../apis/projects_api.dart';
import '../../../models/project_model.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart';

class ProjectMonitoring extends ConsumerWidget {
  const ProjectMonitoring({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(allProjectsProvider);

    return PageFrame(
      title: 'Project Monitoring',
      color: AppColors.admin,
      child: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load projects: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (projects) {
          final active = projects.where((p) => !p.isCompleted).length;
          final completed = projects.length - active;
          final averageProgress = projects.isEmpty
              ? 0
              : (projects.fold<int>(0, (sum, p) => sum + p.progress) /
                        projects.length)
                    .round();
          final impacted = projects.fold<int>(
            0,
            (sum, p) => sum + (p.peopleImpacted ?? 0),
          );

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  Stat('$active', 'Active', AppColors.admin),
                  const SizedBox(width: 8),
                  Stat('$completed', 'Completed', AppColors.admin),
                  const SizedBox(width: 8),
                  Stat('$averageProgress%', 'Avg Progress', AppColors.admin),
                ],
              ),
              if (impacted > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '$impacted people impacted across reported projects',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              section('All Projects'),
              if (projects.isEmpty)
                const AppCard(
                  child: Text(
                    'No projects yet. A project appears when a university '
                    'accepts an assigned challenge.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                )
              else
                for (final project in projects)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ProjectMonitorCard(project: project),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectMonitorCard extends StatelessWidget {
  const _ProjectMonitorCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: 0,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            project.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                '${project.universityName} · ${project.category}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: project.progress / 100,
                  minHeight: 6,
                  backgroundColor: AppColors.line,
                  color: AppColors.admin,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                project.isCompleted
                    ? 'Completed'
                    : '${project.progress}% · ${project.currentMilestone?.name ?? ''}',
                style: const TextStyle(fontSize: 11.5),
              ),
            ],
          ),
          children: [
            if (project.department.isNotEmpty)
              _row('Department', project.department),
            _row('Mentor', project.mentor),
            _row('Challenge', project.challengeTitle),
            if (project.team.isNotEmpty) _row('Team', project.team.join(', ')),
            if (project.hasImpactReport)
              _row('Impact', '${project.peopleImpacted} people'),
            const SizedBox(height: 8),
            for (final milestone in project.milestones)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      milestone.isCompleted
                          ? Icons.check_circle
                          : milestone.isActive
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: milestone.isCompleted || milestone.isActive
                          ? AppColors.admin
                          : AppColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        milestone.name,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Text(
                      milestone.status,
                      style: const TextStyle(
                        fontSize: 11,
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

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
