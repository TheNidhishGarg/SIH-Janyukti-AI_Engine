import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../apis/organizations_api.dart';
import '../../../apis/projects_api.dart';
import '../../../core/routes/app_routes.dart';
import '../../../models/challenge_model.dart';
import '../../../models/industry_interest_model.dart';
import '../../../models/project_model.dart';
import '../../../models/user_model.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart';
import '../../auth/providers/user_provider.dart';
import '../../auth/services/auth_session.dart';
import '../../citizen/controllers/citizen_controller.dart';
import '../../common/ai_widgets.dart';
import '../../common/dialogs.dart';

// ============================================================
// HELPERS
// ============================================================

String _organizationName(
  WidgetRef ref,
  UserModel? user, {
  String fallback = 'Your university',
}) {
  final id = user?.organizationId ?? '';
  if (id.isEmpty) return fallback;
  return ref.watch(organizationProvider(id)).asData?.value?.name ?? fallback;
}

void _showSnack(BuildContext context, String message, {bool error = false}) {
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

String _errorText(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

Widget _emptyCard(String message, {IconData icon = Icons.inbox_outlined}) {
  return AppCard(
    child: Row(
      children: [
        Icon(icon, color: AppColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

String _date(DateTime? date) {
  if (date == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

const _loader = Padding(
  padding: EdgeInsets.all(20),
  child: Center(child: CircularProgressIndicator()),
);

// ============================================================
// DASHBOARD
// ============================================================

class UniversityDashboard extends ConsumerWidget {
  const UniversityDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final organizationId = user?.organizationId ?? '';

    final logout = IconButton(
      tooltip: 'Logout',
      onPressed: () => AuthSession.signOut(context),
      icon: const Icon(Icons.logout_outlined),
    );

    if (organizationId.isEmpty) {
      return PageFrame(
        title: 'University Dashboard',
        color: AppColors.university,
        actions: [logout],
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _emptyCard(
            'This account is not linked to a university organisation. '
            'Contact the JanYukti administrator.',
            icon: Icons.link_off_rounded,
          ),
        ),
      );
    }

    final organizationName = _organizationName(ref, user);
    final challengesAsync = ref.watch(
      assignedChallengesProvider(organizationId),
    );
    final projectsAsync = ref.watch(universityProjectsProvider(organizationId));

    final challenges = challengesAsync.asData?.value ?? const <Challenge>[];
    final projects = projectsAsync.asData?.value ?? const <Project>[];

    final awaiting = challenges
        .where((c) => c.status == ChallengeStatus.assigned && !c.hasProject)
        .toList();
    final active = projects.where((p) => !p.isCompleted).toList();
    final completed = projects.where((p) => p.isCompleted).toList();
    final impacted = projects.fold<int>(
      0,
      (sum, p) => sum + (p.peopleImpacted ?? 0),
    );

    return PageFrame(
      title: 'University Dashboard',
      color: AppColors.university,
      actions: [logout],
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            organizationName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            'Signed in as ${user?.fullName ?? ''}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Stat(
                '${awaiting.length}',
                'New Assignments',
                AppColors.university,
              ),
              const SizedBox(width: 8),
              Stat('${active.length}', 'Active Projects', AppColors.university),
              const SizedBox(width: 8),
              Stat('$impacted', 'People Impacted', AppColors.university),
            ],
          ),

          section('Assigned Challenges'),
          if (challengesAsync.hasError)
            _emptyCard(
              'Could not load assignments: ${_errorText(challengesAsync.error!)}',
              icon: Icons.cloud_off_outlined,
            )
          else if (challengesAsync.isLoading && challenges.isEmpty)
            _loader
          else if (awaiting.isEmpty)
            _emptyCard(
              'No new assignments. Challenges the administrator assigns to '
              'your university appear here instantly.',
            )
          else
            for (final challenge in awaiting)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AssignedChallengeCard(
                  challenge: challenge,
                  onTap: () => Navigator.pushNamed(
                    context,
                    Routes.challengeDetail,
                    arguments: challenge,
                  ),
                ),
              ),

          section('Active Projects'),
          if (projectsAsync.isLoading && projects.isEmpty)
            _loader
          else if (active.isEmpty)
            _emptyCard(
              'Accept an assigned challenge to start a project.',
              icon: Icons.engineering_outlined,
            )
          else
            for (final project in active)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProjectTile(
                  project: project,
                  onTap: () => Navigator.pushNamed(
                    context,
                    Routes.workspace,
                    arguments: project,
                  ),
                ),
              ),

          if (completed.isNotEmpty) ...[
            section('Completed Projects'),
            for (final project in completed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProjectTile(
                  project: project,
                  onTap: () => Navigator.pushNamed(
                    context,
                    Routes.workspace,
                    arguments: project,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AssignedChallengeCard extends StatelessWidget {
  const _AssignedChallengeCard({required this.challenge, required this.onTap});

  final Challenge challenge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final department = challenge.assignedDepartment;
    final score = challenge.matchScore;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  challenge.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PriorityChip(challenge.effectivePriority),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${challenge.category} · ${challenge.location}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (department != null || score != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: AppColors.university,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    department == null
                        ? 'Matched by the AI engine'
                        : 'Matched on $department',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.university,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (score != null)
                  ScoreBadge(
                    percent: (score * 100).round(),
                    color: AppColors.university,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String stage;
    if (!project.isCompleted) {
      stage = 'Current stage: ${project.currentMilestone?.name ?? '-'}';
    } else if (project.hasImpactReport) {
      stage = 'Completed · ${project.peopleImpacted} people impacted';
    } else {
      stage = 'Completed · impact report pending';
    }

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  project.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '${project.progress}%',
                style: const TextStyle(
                  color: AppColors.university,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            project.challengeTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: project.progress / 100,
              minHeight: 7,
              backgroundColor: AppColors.line,
              color: AppColors.university,
            ),
          ),
          const SizedBox(height: 8),
          Text(stage, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ============================================================
// CHALLENGE DETAILS
// ============================================================

class UniversityChallengeDetails extends ConsumerStatefulWidget {
  const UniversityChallengeDetails({super.key, required this.x});

  final Challenge x;

  @override
  ConsumerState<UniversityChallengeDetails> createState() =>
      _UniversityChallengeDetailsState();
}

class _UniversityChallengeDetailsState
    extends ConsumerState<UniversityChallengeDetails> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final challenge =
        ref.watch(challengeStreamProvider(widget.x.id)).asData?.value ??
        widget.x;
    final user = ref.watch(currentUserProvider);
    final organizationName = _organizationName(
      ref,
      user,
      fallback: challenge.assignedUniversityName ?? 'Your university',
    );
    final assignedToUs =
        challenge.isAssigned &&
        challenge.assignedUniversityId == user?.organizationId;
    final projectId = challenge.projectId;
    final photos = challenge.media.where((m) {
      final type = m.type.toLowerCase();
      return m.resourceType.toLowerCase() == 'image' ||
          type == 'photo' ||
          type == 'image';
    }).toList();

    return PageFrame(
      title: 'Challenge Details',
      color: AppColors.university,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            challenge.title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '${challenge.category} · ${challenge.location}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PriorityChip(challenge.effectivePriority),
              StatusPill(challenge.statusLabel),
            ],
          ),
          const SizedBox(height: 18),

          AiInsightCard(
            challenge: challenge,
            accent: AppColors.university,
            forAdmin: true,
          ),

          section('Reported Problem'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  challenge.description,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
                if (challenge.additionalInfo.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Additional information',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(challenge.additionalInfo),
                ],
                const SizedBox(height: 12),
                Text(
                  'Reported by ${challenge.submittedBy.isEmpty ? 'a citizen' : challenge.submittedBy} '
                  'on ${_date(challenge.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),

          if (photos.isNotEmpty) ...[
            section('Photos'),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    photos[index].url,
                    width: 240,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 240,
                      color: AppColors.line,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
          ],

          if (challenge.voiceNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${challenge.voiceNotes.length} voice note(s) attached',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),

          const SizedBox(height: 24),

          if (projectId != null)
            RoleButton(
              label: 'Open Project Workspace',
              color: AppColors.university,
              icon: Icons.work_outline_rounded,
              isLoading: _isBusy,
              onTap: () => _openProject(projectId),
            )
          else if (assignedToUs &&
              challenge.status == ChallengeStatus.assigned) ...[
            RoleButton(
              label: 'Accept & Create Project',
              color: AppColors.university,
              icon: Icons.handshake,
              onTap: () => Navigator.pushNamed(
                context,
                Routes.createProject,
                arguments: challenge,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () => _decline(challenge, organizationName),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Decline Assignment'),
              ),
            ),
          ] else
            _emptyCard(
              'This challenge is no longer assigned to your university.',
              icon: Icons.info_outline_rounded,
            ),
        ],
      ),
    );
  }

  Future<void> _openProject(String projectId) async {
    setState(() => _isBusy = true);
    try {
      final project = await ref.read(projectsApiProvider).getProject(projectId);
      if (!mounted) return;
      if (project == null) {
        _showSnack(context, 'Project not found.', error: true);
        return;
      }
      Navigator.pushNamed(context, Routes.workspace, arguments: project);
    } catch (error) {
      if (mounted) _showSnack(context, _errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _decline(Challenge challenge, String organizationName) async {
    final reason = await askForText(
      context,
      title: 'Decline assignment',
      message:
          'The challenge goes back to the administrator, who can assign it '
          'to another university.',
      hint: 'Why can your university not take this on?',
      confirmLabel: 'Decline',
    );
    if (reason == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await ref
          .read(citizenControllerProvider.notifier)
          .declineAssignment(
            challengeId: challenge.id,
            universityName: organizationName,
            reason: reason,
          );
      if (!mounted) return;
      _showSnack(context, 'Assignment declined');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) _showSnack(context, _errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}

// ============================================================
// CREATE PROJECT
// ============================================================

class CreateProjectView extends ConsumerStatefulWidget {
  const CreateProjectView({super.key, required this.challenge});

  final Challenge challenge;

  @override
  ConsumerState<CreateProjectView> createState() => _CreateProjectViewState();
}

class _CreateProjectViewState extends ConsumerState<CreateProjectView> {
  late final TextEditingController _name = TextEditingController(
    text: widget.challenge.title,
  );
  late final TextEditingController _mentor = TextEditingController(
    text: ref.read(currentUserProvider)?.fullName ?? '',
  );
  final _description = TextEditingController();
  final _member = TextEditingController();
  final List<String> _team = [];
  bool _isCreating = false;

  @override
  void dispose() {
    _name.dispose();
    _mentor.dispose();
    _description.dispose();
    _member.dispose();
    super.dispose();
  }

  void _addMember() {
    final name = _member.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _team.add(name);
      _member.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final organizationName = _organizationName(
      ref,
      user,
      fallback: widget.challenge.assignedUniversityName ?? 'Your university',
    );

    return PageFrame(
      title: 'Create Project',
      color: AppColors.university,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Challenge',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.challenge.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.challenge.category} · ${widget.challenge.location}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Project name *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mentor,
            decoration: const InputDecoration(labelText: 'Faculty mentor *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Approach (optional)',
              hintText: 'How your team plans to solve this',
            ),
          ),

          section('Team members'),
          for (final member in _team)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppCard(
                padding: 6,
                child: ListTile(
                  dense: true,
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(member),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _team.remove(member)),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _member,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addMember(),
                  decoration: const InputDecoration(
                    hintText: 'Add a team member',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _addMember,
                icon: const Icon(Icons.add),
              ),
            ],
          ),

          section('Milestones'),
          const AppCard(
            child: Timeline(
              items: Project.defaultMilestones,
              active: 0,
              color: AppColors.university,
            ),
          ),

          const SizedBox(height: 20),
          RoleButton(
            label: 'Create Project',
            color: AppColors.university,
            icon: Icons.rocket_launch_outlined,
            isLoading: _isCreating,
            onTap: () => _create(organizationName),
          ),
        ],
      ),
    );
  }

  Future<void> _create(String organizationName) async {
    if (_name.text.trim().isEmpty || _mentor.text.trim().isEmpty) {
      _showSnack(
        context,
        'Project name and faculty mentor are required.',
        error: true,
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      final project = await ref
          .read(projectsApiProvider)
          .createForChallenge(
            challenge: widget.challenge,
            name: _name.text,
            mentor: _mentor.text,
            universityName: organizationName,
            team: _team,
            description: _description.text,
          );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        Routes.workspace,
        arguments: project,
      );
    } catch (error) {
      if (mounted) _showSnack(context, _errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }
}

// ============================================================
// PROJECT WORKSPACE
// ============================================================

class ProjectWorkspace extends ConsumerStatefulWidget {
  const ProjectWorkspace({super.key, required this.p});

  final Project p;

  @override
  ConsumerState<ProjectWorkspace> createState() => _ProjectWorkspaceState();
}

class _ProjectWorkspaceState extends ConsumerState<ProjectWorkspace> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final project =
        ref.watch(projectStreamProvider(widget.p.id)).asData?.value ??
        widget.p;

    return DefaultTabController(
      length: 4,
      child: PageFrame(
        title: 'Project Workspace',
        color: AppColors.university,
        actions: [
          IconButton(
            tooltip: 'Project chat',
            onPressed: () =>
                Navigator.pushNamed(context, Routes.chat, arguments: project),
            icon: const Icon(Icons.forum_outlined),
          ),
        ],
        child: Column(
          children: [
            const TabBar(
              labelColor: AppColors.university,
              indicatorColor: AppColors.university,
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Milestones'),
                Tab(text: 'Team'),
                Tab(text: 'Partners'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _overview(project),
                  _milestones(project),
                  _team(project),
                  _partners(project),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview(Project project) {
    final current = project.currentMilestone;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          project.name,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(project.challengeTitle, style: const TextStyle(color: AppColors.muted)),
        if (project.department.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              project.department,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.university,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Progress',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${project.progress}%',
                    style: const TextStyle(
                      color: AppColors.university,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: project.progress / 100,
                  minHeight: 9,
                  backgroundColor: AppColors.line,
                  color: AppColors.university,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                current == null
                    ? 'All milestones complete'
                    : 'Current stage: ${current.name}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (current != null)
          RoleButton(
            label: 'Mark "${current.name}" complete',
            color: AppColors.university,
            icon: Icons.check_circle_outline,
            isLoading: _isBusy,
            onTap: () => _completeMilestone(project, current),
          ),

        if (project.isCompleted && !project.hasImpactReport)
          RoleButton(
            label: 'Report Impact',
            color: AppColors.university,
            icon: Icons.volunteer_activism_outlined,
            isLoading: _isBusy,
            onTap: () => _reportImpact(project),
          ),

        if (project.hasImpactReport)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Impact reported',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '${project.peopleImpacted} people impacted',
                  style: const TextStyle(
                    color: AppColors.university,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                if (project.impactSummary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(project.impactSummary),
                ],
              ],
            ),
          ),

        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, Routes.chat, arguments: project),
            icon: const Icon(Icons.forum_outlined),
            label: const Text('Open Project Chat'),
          ),
        ),

        section('The Challenge'),
        AppCard(
          child: Text(
            project.description,
            style: const TextStyle(height: 1.45),
          ),
        ),
      ],
    );
  }

  Widget _milestones(Project project) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        for (final milestone in project.milestones)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: 6,
              child: ListTile(
                leading: Icon(
                  milestone.isCompleted
                      ? Icons.check_circle
                      : milestone.isActive
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: milestone.isCompleted || milestone.isActive
                      ? AppColors.university
                      : AppColors.muted,
                ),
                title: Text(
                  milestone.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  milestone.isCompleted
                      ? [
                          'Completed ${_date(milestone.completedAt)}',
                          if (milestone.note.isNotEmpty) milestone.note,
                        ].join(' · ')
                      : milestone.status,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _team(Project project) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        AppCard(
          padding: 6,
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
            title: Text(project.mentor.isEmpty ? 'Not set' : project.mentor),
            subtitle: const Text('Faculty mentor'),
          ),
        ),
        section('Team members'),
        if (project.team.isEmpty)
          _emptyCard('No team members listed.', icon: Icons.group_outlined)
        else
          for (final member in project.team)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppCard(
                padding: 6,
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(member),
                ),
              ),
            ),
      ],
    );
  }

  Widget _partners(Project project) {
    final interestsAsync = ref.watch(projectInterestsProvider(project.id));

    return interestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load partners: ${_errorText(error)}'),
        ),
      ),
      data: (interests) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (interests.isEmpty)
            _emptyCard(
              'No industry partners yet. Partners who offer support for this '
              'project appear here.',
              icon: Icons.handshake_outlined,
            )
          else
            for (final interest in interests)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InterestCard(interest: interest),
              ),
        ],
      ),
    );
  }

  Future<void> _completeMilestone(
    Project project,
    ProjectMilestone milestone,
  ) async {
    final isLast = project.milestones.where((m) => !m.isCompleted).length == 1;
    final note = await askForText(
      context,
      title: 'Complete "${milestone.name}"',
      message: isLast
          ? 'This is the final milestone. The citizen will see the solution as deployed.'
          : 'The citizen sees progress update live on their tracking screen.',
      hint: 'What was achieved (optional)',
      confirmLabel: 'Mark complete',
      required: false,
    );
    if (note == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await ref
          .read(projectsApiProvider)
          .completeCurrentMilestone(project.id, note: note);
      if (mounted) _showSnack(context, '${milestone.name} marked complete');
    } catch (error) {
      if (mounted) _showSnack(context, _errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _reportImpact(Project project) async {
    final result = await showDialog<({int people, String summary})>(
      context: context,
      builder: (_) => const _ImpactDialog(),
    );
    if (result == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await ref
          .read(projectsApiProvider)
          .reportImpact(
            project,
            peopleImpacted: result.people,
            summary: result.summary,
          );
      if (mounted) {
        _showSnack(context, 'Impact reported. The challenge is now resolved.');
      }
    } catch (error) {
      if (mounted) _showSnack(context, _errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}

class _InterestCard extends StatelessWidget {
  const _InterestCard({required this.interest});

  final IndustryInterest interest;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            interest.organizationName.isEmpty
                ? 'Industry partner'
                : interest.organizationName,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          if (interest.userName.isNotEmpty)
            Text(
              interest.userName,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final support in interest.support)
                Chip(
                  label: Text(support),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (interest.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(interest.message, style: const TextStyle(height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _ImpactDialog extends StatefulWidget {
  const _ImpactDialog();

  @override
  State<_ImpactDialog> createState() => _ImpactDialogState();
}

class _ImpactDialogState extends State<_ImpactDialog> {
  final _people = TextEditingController();
  final _summary = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _people.dispose();
    _summary.dispose();
    super.dispose();
  }

  void _submit() {
    final people = int.tryParse(_people.text.trim());
    if (people == null || people < 0) {
      setState(() => _error = 'Enter the number of people reached.');
      return;
    }
    Navigator.pop(context, (people: people, summary: _summary.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report impact'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _people,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'People impacted *',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _summary,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'What changed for them?',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.university),
          child: const Text('Report'),
        ),
      ],
    );
  }
}
