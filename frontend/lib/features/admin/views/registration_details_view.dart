import 'package:flutter/material.dart';
import '../../../apis/admin_api.dart';
import '../../../models/user_model.dart';
import '../../../models/user_role.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart';
import '../../auth/controllers/auth_controller.dart';
import 'registration_approvals_view.dart';

class RegistrationDetailsView extends StatefulWidget {
  const RegistrationDetailsView({super.key, required this.user});
  final UserModel user;
  @override
  State<RegistrationDetailsView> createState() =>
      _RegistrationDetailsViewState();
}

class _RegistrationDetailsViewState extends State<RegistrationDetailsView> {
  final api = AdminApi();
  late Future<RegistrationRequest> request = api.getRequest(widget.user);
  bool busy = false;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: PageFrame(
      title: 'Registration Details',
      color: AppColors.admin,
      child: FutureBuilder<RegistrationRequest>(
        future: request,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(authErrorMessage(snapshot.error!)),
                  TextButton(
                    onPressed: () =>
                        setState(() => request = api.getRequest(widget.user)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data!.user;
          final org = snapshot.data!.organization;
          final details = <String, String?>{
            'Role': getRoleConfig(user.role).title,
            'Name': snapshot.data!.name,
            if (org != null) ...{
              'University Type': org.category,
              'Industry Sector': org.sector,
              'Website': org.website,
              'Address': org.address,
              'City': org.city,
              'State': org.state,
            },
            'Official Email': user.email,
            'Phone': user.phone,
            'Contact Person': user.fullName,
            'Designation': user.designation,
            'Registration Date': registrationDate(user.createdAt),
            'Status': user.status,
          };
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final field in details.entries.where(
                      (e) => e.value != null && e.value!.isNotEmpty,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SelectableText(field.value!),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (busy) const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => decide(false),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: busy ? null : () => decide(true),
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
  Future<void> decide(bool approve) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => _DecisionDialog(approve: approve),
      );
      if (reason == null || !mounted) return;
      if (approve) {
        await api.approveRegistration(uid: widget.user.uid);
      } else {
        await api.rejectRegistration(uid: widget.user.uid, reason: reason);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Registration approved successfully.'
                : 'Registration rejected successfully.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.approve});
  final bool approve;
  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.approve
          ? 'Approve this registration?'
          : 'Reject this registration?',
    ),
    content: widget.approve
        ? null
        : Form(
            key: form,
            child: TextFormField(
              controller: reason,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for rejection',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'A rejection reason is required.'
                  : null,
            ),
          ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (widget.approve || form.currentState!.validate()) {
            Navigator.pop(context, reason.text.trim());
          }
        },
        child: Text(widget.approve ? 'Approve' : 'Reject'),
      ),
    ],
  );
}
