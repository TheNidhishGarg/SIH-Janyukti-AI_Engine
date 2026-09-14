import 'package:flutter/material.dart';
import '../../../apis/admin_api.dart';
import '../../../core/routes/app_routes.dart';
import '../../../models/user_model.dart';
import '../../../models/user_role.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart';
import '../../auth/controllers/auth_controller.dart';

String registrationDate(DateTime? date) => date == null
    ? 'Not recorded'
    : '${date.toLocal().day}/${date.toLocal().month}/${date.toLocal().year}';

class RegistrationApprovalsView extends StatefulWidget {
  const RegistrationApprovalsView({super.key});
  @override
  State<RegistrationApprovalsView> createState() =>
      _RegistrationApprovalsViewState();
}

class _RegistrationApprovalsViewState extends State<RegistrationApprovalsView> {
  UserRole? filter;
  late final stream = AdminApi().watchPendingRegistrations();
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Registration Requests',
    color: AppColors.admin,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final entry in <UserRole?, String>{
                null: 'All',
                UserRole.university: 'Universities',
                UserRole.industry: 'Industries',
                UserRole.admin: 'Admins',
              }.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: filter == entry.key,
                  onSelected: (_) => setState(() => filter = entry.key),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<UserModel>>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text(authErrorMessage(snapshot.error!)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final users = snapshot.data!
                  .where((u) => filter == null || u.role == filter)
                  .toList();
              if (users.isEmpty) {
                return const Center(
                  child: Text('No pending registration requests.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: users.length,
                itemBuilder: (_, index) => RegistrationRequestCard(
                  user: users[index],
                  key: ValueKey(users[index].uid),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class RegistrationRequestCard extends StatefulWidget {
  const RegistrationRequestCard({super.key, required this.user});
  final UserModel user;
  @override
  State<RegistrationRequestCard> createState() =>
      _RegistrationRequestCardState();
}

class _RegistrationRequestCardState extends State<RegistrationRequestCard> {
  late Future<RegistrationRequest> request = AdminApi().getRequest(widget.user);
  @override
  void didUpdateWidget(covariant RegistrationRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      request = AdminApi().getRequest(widget.user);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RegistrationRequest>(
    future: request,
    builder: (context, snapshot) {
      final user = widget.user;
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              snapshot.data?.name ?? user.fullName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Text(getRoleConfig(user.role).title),
            Text(user.email),
            Text(user.phone ?? ''),
            Text(
              [
                user.city,
                user.state,
              ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
            ),
            Text('Registered: ${registrationDate(user.createdAt)}'),
            StatusPill(user.status),
            if (snapshot.hasError) Text(authErrorMessage(snapshot.error!)),
            TextButton(
              onPressed: () => Navigator.pushNamed(
                context,
                Routes.registrationDetails,
                arguments: user,
              ),
              child: const Text('View Details'),
            ),
          ],
        ),
      );
    },
  );
}

class RegistrationApprovalsPreview extends StatefulWidget {
  const RegistrationApprovalsPreview({super.key});
  @override
  State<RegistrationApprovalsPreview> createState() =>
      _RegistrationApprovalsPreviewState();
}

class _RegistrationApprovalsPreviewState
    extends State<RegistrationApprovalsPreview> {
  late final stream = AdminApi().watchPendingRegistrations();
  @override
  Widget build(BuildContext context) => StreamBuilder<List<UserModel>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return AppCard(child: Text(authErrorMessage(snapshot.error!)));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final users = snapshot.data!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section('Pending Registration Requests'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Registrations: ${users.length}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                for (final role in [
                  UserRole.university,
                  UserRole.industry,
                  UserRole.admin,
                ])
                  Text(
                    '${getRoleConfig(role).title}: ${users.where((u) => u.role == role).length}',
                  ),
                TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, Routes.approvals),
                  child: const Text('View All'),
                ),
              ],
            ),
          ),
          if (users.isEmpty) const Text('No pending registration requests.'),
          for (final user in users.take(3))
            RegistrationRequestCard(key: ValueKey(user.uid), user: user),
        ],
      );
    },
  );
}

class OrganizationOverview extends StatefulWidget {
  const OrganizationOverview({super.key, required this.challengeCount});
  final int challengeCount;
  @override
  State<OrganizationOverview> createState() => _OrganizationOverviewState();
}

class _OrganizationOverviewState extends State<OrganizationOverview> {
  late final stream = AdminApi().watchOrganizationCounts();
  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, int>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Text(authErrorMessage(snapshot.error!));
      return Row(
        children: [
          Stat('${widget.challengeCount}', 'Challenges', AppColors.admin),
          Stat(
            snapshot.hasData ? '${snapshot.data!['university']}' : '…',
            'Universities',
            AppColors.admin,
          ),
          Stat(
            snapshot.hasData ? '${snapshot.data!['industry']}' : '…',
            'Industries',
            AppColors.admin,
          ),
        ],
      );
    },
  );
}
