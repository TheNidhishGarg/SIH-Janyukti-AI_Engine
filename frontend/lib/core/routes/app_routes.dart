import '../../features/admin/views/analytics_view.dart';
import '../../features/admin/views/challange_review.dart';
import '../../features/admin/views/project_monitoring.dart';
import '../../features/auth/views/registration_screen.dart';
import '../../features/auth/views/session_gate.dart';
import '../../features/admin/views/registration_approvals_view.dart';
import '../../features/admin/views/registration_details_view.dart';
import '../../models/user_role.dart';
import '../../models/user_model.dart';
import 'package:flutter/material.dart';
import '../../features/auth/views/otp_view.dart';
import '../../features/auth/views/role_selection_screen.dart';
import '../../features/auth/views/welcome_view.dart';
import '../../features/citizen/views/citizen_dashboard.dart'
    show CitizenDashboard;
import '../../features/citizen/views/submit_challange_view.dart';
import '../../features/citizen/views/submit_success_screen.dart';
import '../../features/citizen/views/trach_challange_view.dart';
import '../../features/university/views/university_views.dart';
import '../../features/industry/views/industry_views.dart';
import '../../features/admin/views/admin_views.dart';
import '../../models/challenge_model.dart';
import '../../models/project_model.dart';

class Routes {
  static const welcome = '/',
      roleSelection = '/roles',
      login = '/login',
      otp = '/otp',
      registration = '/register',
      pending = '/account-status',
      approvals = '/admin/approvals',
      registrationDetails = '/admin/registration',
      citizen = '/citizen',
      submit = '/submit',
      details = '/details',
      success = '/success',
      track = '/track',
      university = '/university',
      challengeDetail = '/university/challenge',
      createProject = '/university/create',
      workspace = '/university/workspace',
      industry = '/industry',
      projectDetail = '/industry/project',
      interest = '/industry/interest',
      collaborations = '/industry/collaborations',
      chat = '/project/chat',
      admin = '/admin',
      review = '/admin/review',
      analytics = '/admin/analytics',
      monitoring = '/admin/projects';
}

class AppRoutes {
  static Route<dynamic> generate(RouteSettings x) {
    final a = x.arguments;
    Widget page;
    switch (x.name) {
      case Routes.welcome:
        page = const SessionGate(restore: true, child: WelcomeView());
        break;
      case Routes.login:
      case Routes.roleSelection:
        page = const RoleSelectionScreen();
        break;
      case Routes.registration:
        page = a is UserRole
            ? RegistrationScreen(role: a)
            : const RoleSelectionScreen();
        break;
      case Routes.pending:
        page = const SessionGate(statusPage: true, child: SizedBox.shrink());
        break;
      case Routes.approvals:
        page = const RegistrationApprovalsView();
        break;
      case Routes.registrationDetails:
        page = RegistrationDetailsView(user: a as UserModel);
        break;
      case Routes.otp:
        page = const OtpView();
        break;
      case Routes.citizen:
        page = const CitizenDashboard();
        break;
      case Routes.submit:
        page = const SubmitChallengeView();
        break;
      case Routes.success:
        page = SubmissionSuccess(challenge: a as Challenge);
        break;
      case Routes.track:
        // Accept either the document id or the challenge itself.
        page = TrackChallengeView(
          challengeId: a is Challenge ? a.id : a as String,
        );
        break;
      case Routes.university:
        page = const UniversityDashboard();
        break;
      case Routes.challengeDetail:
        page = UniversityChallengeDetails(x: a as Challenge);
        break;
      case Routes.createProject:
        page = CreateProjectView(challenge: a as Challenge);
        break;
      case Routes.workspace:
        page = ProjectWorkspace(p: a as Project);
        break;
      case Routes.industry:
        page = const IndustryDashboard();
        break;
      case Routes.projectDetail:
        page = ProjectDetails(p: a as Project);
        break;
      case Routes.interest:
        page = ExpressInterest(p: a as Project);
        break;
      case Routes.collaborations:
        page = const Collaborations();
        break;
      case Routes.chat:
        page = CollaborationChat(project: a as Project);
        break;
      case Routes.admin:
        page = const AdminDashboard();
        break;
      case Routes.review:
        page = ChallengeReview(x: a as Challenge);
        break;
      case Routes.analytics:
        page = const AnalyticsView();
        break;
      case Routes.monitoring:
        page = const ProjectMonitoring();
        break;
      default:
        page = const SessionGate(restore: true, child: WelcomeView());
    }
    final requiredRole = switch (x.name) {
      Routes.citizen ||
      Routes.submit ||
      Routes.details ||
      Routes.success ||
      Routes.track => UserRole.citizen,
      Routes.university ||
      Routes.challengeDetail ||
      Routes.createProject ||
      Routes.workspace => UserRole.university,
      Routes.industry ||
      Routes.projectDetail ||
      Routes.interest ||
      Routes.collaborations => UserRole.industry,
      Routes.admin ||
      Routes.review ||
      Routes.analytics ||
      Routes.monitoring ||
      Routes.approvals ||
      Routes.registrationDetails => UserRole.admin,
      _ => null,
    };
    final Widget guardedPage;
    if (requiredRole != null) {
      guardedPage = SessionGate(requiredRole: requiredRole, child: page);
    } else if (x.name == Routes.chat) {
      // Project chat is shared by the university team and industry partners,
      // so it needs an active account of any role rather than one role.
      guardedPage = SessionGate(child: page);
    } else {
      guardedPage = page;
    }
    return MaterialPageRoute(settings: x, builder: (_) => guardedPage);
  }
}
