import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../apis/organizations_api.dart';
import '../../../apis/projects_api.dart';
import '../../../core/routes/app_routes.dart';
import '../../../models/chat_message_model.dart';
import '../../../models/industry_interest_model.dart';
import '../../../models/project_model.dart';
import '../../../models/user_model.dart';
import '../../../models/user_role.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart';
import '../../auth/providers/user_provider.dart';
import '../../auth/services/auth_session.dart';

// ============================================================
// HELPERS
// ============================================================

/// App categories an industry sector is most likely to back, so the
/// dashboard can lead with relevant projects.
const _sectorCategories = <String, List<String>>{
  'Healthcare': ['Healthcare'],
  'Agriculture': ['Agriculture'],
  'Energy': ['Infrastructure'],
  'Construction': ['Infrastructure'],
  'Transportation': ['Infrastructure'],
  'Manufacturing': ['Infrastructure', 'Waste Management'],
  'Environment': ['Water Management', 'Waste Management'],
  'Education': ['Education'],
};

/// Interests are keyed by the partner's organisation; fall back to the user
/// for accounts without one.
String _partnerId(UserModel? user) {
  final organizationId = user?.organizationId ?? '';
  return organizationId.isNotEmpty ? organizationId : (user?.uid ?? '');
}

String _partnerName(WidgetRef ref, UserModel? user) {
  final organizationId = user?.organizationId ?? '';
  final fallback = user?.fullName ?? 'Industry partner';
  if (organizationId.isEmpty) return fallback;
  return ref.watch(organizationProvider(organizationId)).asData?.value?.name ??
      fallback;
}

List<IndustryInterest> _myInterests(WidgetRef ref, UserModel? user) {
  final partnerId = _partnerId(user);
  if (partnerId.isEmpty) return const [];
  return ref.watch(organizationInterestsProvider(partnerId)).asData?.value ??
      const [];
}

IndustryInterest? _interestFor(List<IndustryInterest> interests, String id) {
  for (final interest in interests) {
    if (interest.projectId == id) return interest;
  }
  return null;
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

Widget _tag(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

// ============================================================
// DASHBOARD
// ============================================================

class IndustryDashboard extends ConsumerWidget {
  const IndustryDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final organizationId = user?.organizationId ?? '';
    final organization = organizationId.isEmpty
        ? null
        : ref.watch(organizationProvider(organizationId)).asData?.value;

    final projectsAsync = ref.watch(allProjectsProvider);
    final projects = projectsAsync.asData?.value ?? const <Project>[];
    final interests = _myInterests(ref, user);
    final interestedIds = {for (final interest in interests) interest.projectId};

    final focus = _sectorCategories[organization?.sector] ?? const <String>[];
    final open = projects.where((p) => !p.isCompleted).toList()
      ..sort((a, b) {
        final rankA = focus.contains(a.category) ? 0 : 1;
        final rankB = focus.contains(b.category) ? 0 : 1;
        if (rankA != rankB) return rankA.compareTo(rankB);
        return b.progress.compareTo(a.progress);
      });
    final sector = organization?.sector;

    return PageFrame(
      title: 'Industry Dashboard',
      color: AppColors.industry,
      actions: [
        IconButton(
          tooltip: 'Logout',
          onPressed: () => AuthSession.signOut(context),
          icon: const Icon(Icons.logout_outlined),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            organization?.name ?? user?.fullName ?? 'Industry partner',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          if (sector != null)
            Text(
              '$sector sector',
              style: const TextStyle(color: AppColors.muted),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Stat('${open.length}', 'Open Projects', AppColors.industry),
              const SizedBox(width: 8),
              Stat('${interests.length}', 'My Offers', AppColors.industry),
              const SizedBox(width: 8),
              Stat(
                '${projects.length - open.length}',
                'Completed',
                AppColors.industry,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, Routes.collaborations),
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('My Collaborations'),
            ),
          ),

          section(
            focus.isEmpty
                ? 'Projects Seeking Support'
                : 'Recommended for Your Sector',
          ),
          if (projectsAsync.hasError)
            _emptyCard(
              'Could not load projects: ${_errorText(projectsAsync.error!)}',
              icon: Icons.cloud_off_outlined,
            )
          else if (projectsAsync.isLoading && projects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (open.isEmpty)
            _emptyCard(
              'No active projects yet. University projects appear here as '
              'soon as they start.',
              icon: Icons.engineering_outlined,
            )
          else
            for (final project in open)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ProjectCard(
                  project,
                  interested: interestedIds.contains(project.id),
                  recommended: focus.contains(project.category),
                  onTap: () => Navigator.pushNamed(
                    context,
                    Routes.projectDetail,
                    arguments: project,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard(
    this.p, {
    super.key,
    this.onTap,
    this.interested = false,
    this.recommended = false,
  });

  final Project p;
  final VoidCallback? onTap;
  final bool interested;
  final bool recommended;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                p.name,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
            if (interested)
              _tag('Offer sent', AppColors.industry)
            else if (recommended)
              _tag('Recommended', AppColors.success),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${p.universityName} · ${p.category}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        if (p.location.isNotEmpty)
          Text(
            p.location,
            style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
          ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: p.progress / 100,
            minHeight: 6,
            backgroundColor: AppColors.line,
            color: AppColors.industry,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          p.isCompleted
              ? 'Completed'
              : '${p.progress}% · ${p.currentMilestone?.name ?? ''}',
          style: const TextStyle(fontSize: 11.5),
        ),
      ],
    ),
  );
}

// ============================================================
// PROJECT DETAILS
// ============================================================

class ProjectDetails extends ConsumerWidget {
  const ProjectDetails({super.key, required this.p});

  final Project p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectStreamProvider(p.id)).asData?.value ?? p;
    final user = ref.watch(currentUserProvider);
    final myInterest = _interestFor(_myInterests(ref, user), project.id);

    return PageFrame(
      title: 'Project Details',
      color: AppColors.industry,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            project.name,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            project.department.isEmpty
                ? project.universityName
                : '${project.universityName} · ${project.department}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(
                  Icons.report_problem_outlined,
                  'Challenge',
                  project.challengeTitle,
                ),
                _infoRow(Icons.category_outlined, 'Category', project.category),
                _infoRow(
                  Icons.location_on_outlined,
                  'Location',
                  project.location,
                ),
                _infoRow(Icons.person_outline, 'Faculty mentor', project.mentor),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: project.progress / 100,
                    minHeight: 8,
                    backgroundColor: AppColors.line,
                    color: AppColors.industry,
                  ),
                ),
                const SizedBox(height: 6),
                Text('${project.progress}% complete'),
              ],
            ),
          ),

          section('About the Problem'),
          AppCard(
            child: Text(
              project.description,
              style: const TextStyle(height: 1.45),
            ),
          ),

          section('Milestones'),
          AppCard(
            child: Timeline(
              items: project.milestoneNames,
              active: project.isCompleted
                  ? project.milestones.length
                  : project.activeMilestone,
              color: AppColors.industry,
            ),
          ),

          const SizedBox(height: 20),

          if (myInterest != null) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your offer',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final support in myInterest.support)
                        Chip(
                          label: Text(support),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  if (myInterest.message.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(myInterest.message),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (!project.isCompleted)
            RoleButton(
              label: myInterest == null ? 'Express Interest' : 'Update Offer',
              color: AppColors.industry,
              icon: Icons.volunteer_activism,
              onTap: () => Navigator.pushNamed(
                context,
                Routes.interest,
                arguments: project,
              ),
            ),

          if (myInterest != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(
                  context,
                  Routes.chat,
                  arguments: project,
                ),
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Open Project Chat'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.industry),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EXPRESS INTEREST
// ============================================================

class ExpressInterest extends ConsumerStatefulWidget {
  const ExpressInterest({super.key, required this.p});

  final Project p;

  @override
  ConsumerState<ExpressInterest> createState() => _ExpressInterestState();
}

class _ExpressInterestState extends ConsumerState<ExpressInterest> {
  final Set<String> _selected = {};
  final _message = TextEditingController();
  bool _prefilled = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final organizationName = _partnerName(ref, user);
    final existing = _interestFor(_myInterests(ref, user), widget.p.id);

    // Prefill an earlier offer once, after this frame, because changing a
    // controller's text notifies listeners and must not happen during build.
    if (!_prefilled && existing != null) {
      _prefilled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selected.addAll(existing.support);
          _message.text = existing.message;
        });
      });
    }

    return PageFrame(
      title: 'Express Interest',
      color: AppColors.industry,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'How can $organizationName help?',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.p.name} · ${widget.p.universityName}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          for (final option in IndustryInterest.supportOptions)
            CheckboxListTile(
              value: _selected.contains(option),
              onChanged: _isSaving
                  ? null
                  : (checked) => setState(
                      () => checked == true
                          ? _selected.add(option)
                          : _selected.remove(option),
                    ),
              title: Text(option),
              activeColor: AppColors.industry,
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Message to the university team',
              hintText: 'What you can offer and any conditions',
            ),
          ),
          const SizedBox(height: 20),
          RoleButton(
            label: existing == null ? 'Submit Interest' : 'Update Offer',
            color: AppColors.industry,
            icon: Icons.send_rounded,
            isLoading: _isSaving,
            onTap: () => _save(user, organizationName),
          ),
        ],
      ),
    );
  }

  Future<void> _save(UserModel? user, String organizationName) async {
    if (user == null) return;
    if (_selected.isEmpty) {
      _showSnack(context, 'Choose at least one way to help.', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(projectsApiProvider)
          .expressInterest(
            project: widget.p,
            user: user,
            organizationName: organizationName,
            support: [
              for (final option in IndustryInterest.supportOptions)
                if (_selected.contains(option)) option,
            ],
            message: _message.text,
          );
      if (!mounted) return;
      _showSnack(context, 'Offer sent to ${widget.p.universityName}');
      Navigator.pushReplacementNamed(context, Routes.collaborations);
    } catch (error) {
      if (mounted) _showSnack(context, _errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ============================================================
// COLLABORATIONS
// ============================================================

class Collaborations extends ConsumerStatefulWidget {
  const Collaborations({super.key});

  @override
  ConsumerState<Collaborations> createState() => _CollaborationsState();
}

class _CollaborationsState extends ConsumerState<Collaborations> {
  String? _openingId;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final partnerId = _partnerId(user);
    final interestsAsync = partnerId.isEmpty
        ? const AsyncData<List<IndustryInterest>>([])
        : ref.watch(organizationInterestsProvider(partnerId));

    return PageFrame(
      title: 'My Collaborations',
      color: AppColors.industry,
      child: interestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load your offers: ${_errorText(error)}'),
          ),
        ),
        data: (interests) => ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (interests.isEmpty)
              _emptyCard(
                'You have not offered support on any project yet. Browse '
                'projects on your dashboard.',
                icon: Icons.handshake_outlined,
              )
            else
              for (final interest in interests)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          interest.projectName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          interest.universityName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
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
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _openingId != null
                                  ? null
                                  : () => _open(interest.projectId, chat: false),
                              child: const Text('View project'),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.icon(
                              onPressed: _openingId != null
                                  ? null
                                  : () => _open(interest.projectId, chat: true),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.industry,
                              ),
                              icon: _openingId == interest.projectId
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.forum_outlined, size: 18),
                              label: const Text('Chat'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(String projectId, {required bool chat}) async {
    setState(() => _openingId = projectId);
    try {
      final project = await ref.read(projectsApiProvider).getProject(projectId);
      if (!mounted) return;
      if (project == null) {
        _showSnack(context, 'This project no longer exists.', error: true);
        return;
      }
      Navigator.pushNamed(
        context,
        chat ? Routes.chat : Routes.projectDetail,
        arguments: project,
      );
    } catch (error) {
      if (mounted) _showSnack(context, _errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }
}

// ============================================================
// PROJECT CHAT
//
// Shared by the university team and industry partners on a project.
// ============================================================

class CollaborationChat extends ConsumerStatefulWidget {
  const CollaborationChat({super.key, required this.project});

  final Project project;

  @override
  ConsumerState<CollaborationChat> createState() => _CollaborationChatState();
}

class _CollaborationChatState extends ConsumerState<CollaborationChat> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final messagesAsync = ref.watch(projectMessagesProvider(widget.project.id));
    final messages = messagesAsync.asData?.value ?? const <ChatMessage>[];
    final color = user?.role == UserRole.university
        ? AppColors.university
        : AppColors.industry;

    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }

    final Widget body;
    if (messagesAsync.hasError) {
      body = const Center(child: Text('Could not load messages.'));
    } else if (messages.isEmpty) {
      body = Center(
        child: Text(
          messagesAsync.isLoading
              ? 'Loading messages...'
              : 'No messages yet. Start the conversation.',
          style: const TextStyle(color: AppColors.muted),
        ),
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          return _Bubble(
            message: message,
            mine: message.senderUid == user?.uid,
            color: color,
          );
        },
      );
    }

    return PageFrame(
      title: 'Project Chat',
      color: color,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: color.withValues(alpha: .06),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.project.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${widget.project.universityName} team and industry partners',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Expanded(child: body),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(user),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : () => _send(user),
                    icon: Icon(Icons.send, color: color),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send(UserModel? user) async {
    final text = _text.text.trim();
    if (text.isEmpty || user == null || _sending) return;

    setState(() => _sending = true);
    try {
      await ref
          .read(projectsApiProvider)
          .sendMessage(projectId: widget.project.id, text: text, user: user);
      _text.clear();
    } catch (error) {
      if (mounted) _showSnack(context, _errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.color,
  });

  final ChatMessage message;
  final bool mine;
  final Color color;

  static String _roleLabel(String role) => switch (role) {
    'university' => 'University',
    'industry' => 'Industry',
    'admin' => 'Admin',
    _ => 'Citizen',
  };

  @override
  Widget build(BuildContext context) {
    final time = message.createdAt;
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          decoration: BoxDecoration(
            color: mine ? color : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: mine ? null : Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  '${message.senderName} · ${_roleLabel(message.senderRole)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              Text(
                message.text,
                style: TextStyle(color: mine ? Colors.white : AppColors.ink),
              ),
              const SizedBox(height: 2),
              Text(
                stamp,
                style: TextStyle(
                  fontSize: 10,
                  color: mine ? Colors.white70 : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
