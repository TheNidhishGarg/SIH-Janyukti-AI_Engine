import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/user_role.dart';
import '../controllers/auth_controller.dart';
import '../providers/user_provider.dart';
import '../services/auth_session.dart';
import 'pending_approval_screen.dart';
import 'welcome_view.dart';

/// All routes share the same persisted Firebase session and live user provider.
class SessionGate extends ConsumerStatefulWidget {
  const SessionGate({
    super.key,
    required this.child,
    this.requiredRole,
    this.restore = false,
    this.statusPage = false,
  });
  final Widget child;
  final UserRole? requiredRole;
  final bool restore, statusPage;
  @override
  ConsumerState<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<SessionGate> {
  String? scheduledRoute;
  late final bool restoreSession =
      widget.restore && ref.read(authApiProvider).currentUser != null;
  void redirect(UserRole role) {
    final route = AuthController.dashboardRoute(role);
    if (scheduledRoute == route) return;
    scheduledRoute = route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(currentUserProvider);
      if (mounted && current?.isActive == true && current?.role == role) {
        Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
      } else {
        scheduledRoute = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider);
    // A signed-out welcome page must not navigate while registration is writing
    // its profile. Login/registration controllers handle that transition.
    if (widget.restore && !restoreSession) return widget.child;
    return session.state.when(
      loading: () => loading,
      error: (failure, _) => error(authErrorMessage(failure)),
      data: (profile) {
        if (!session.isSignedIn) return const WelcomeView();
        if (profile == null) {
          return error(
            'Unable to verify your account profile. Check your connection or contact the janYukti administrator.',
          );
        }
        if (widget.requiredRole != null &&
            profile.role != widget.requiredRole) {
          return error('This account does not belong to the selected portal.');
        }
        if (!profile.isActive) return PendingApprovalScreen(profile: profile);
        if (widget.restore || widget.statusPage) {
          redirect(profile.role);
          return loading;
        }
        return widget.child;
      },
    );
  }

  Widget get loading =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
  Widget error(String message) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              TextButton(
                onPressed: () => ref.read(userSessionProvider).refresh(),
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => AuthSession.signOut(context),
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
