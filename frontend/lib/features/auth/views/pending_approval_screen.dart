import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/auth_controller.dart';
import 'package:flutter/material.dart';
import '../../../models/user_model.dart';
import '../../../models/user_role.dart';
import '../../../widgets/ui.dart';

class PendingApprovalScreen extends ConsumerWidget {
  const PendingApprovalScreen({super.key, required this.profile});
  final UserModel profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: 'Account Status',
    color: getRoleConfig(profile.role).primaryColor,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.account_circle_outlined, size: 72),
        const SizedBox(height: 24),
        StatusPill(profile.status),
        const SizedBox(height: 24),
        Text(switch (profile.status) {
          'pending' =>
            'Your registration has been submitted.\n\nYour janYukti account is waiting for administrator approval.\n\nYou will be able to access your dashboard after approval.',
          'rejected' =>
            'Your registration request was rejected.${profile.rejectionReason == null ? '' : '\n\n${profile.rejectionReason}'}',
          'suspended' =>
            'Your janYukti account has been suspended.\nPlease contact the janYukti administrator.',
          _ =>
            'Your account status is unavailable. Please contact the janYukti administrator.',
        }, style: const TextStyle(fontSize: 17)),
        const SizedBox(height: 32),
        RoleButton(
          label: 'Logout',
          isLoading: ref.watch(authControllerProvider).isLoading,
          color: getRoleConfig(profile.role).primaryColor,
          onTap: () => ref.read(authControllerProvider).logout(context),
        ),
      ],
    ),
  );
}
