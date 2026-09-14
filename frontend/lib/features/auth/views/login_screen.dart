import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/user_role.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_text_field.dart';
import '../../../core/routes/app_routes.dart';
import 'role_selection_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.role});
  final UserRole role;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final identifier = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;

  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final role = getRoleConfig(widget.role);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: auth.isLoading
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(height: 18),
                  AuthHeader(
                    icon: role.icon,
                    title: '${role.title} Portal',
                    subtitle: _subtitle,
                    color: role.primaryColor,
                  ),
                  const SizedBox(height: 38),
                  _emailInputs(auth, role.emailLabel),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: auth.isLoading ? null : _resetPassword,
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: role.primaryColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (auth.errorMessage != null) _error(auth.errorMessage!),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: auth.isLoading
                          ? null
                          : () => _continueAuth(auth),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: role.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(
                              width: 23,
                              height: 23,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              role.loginLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(switch (widget.role) {
                    UserRole.citizen => 'New to janYukti?',
                    UserRole.university => 'Representing a university?',
                    UserRole.industry => 'Representing an organization?',
                    UserRole.admin =>
                      'Need administrative access? Approval is required.',
                  }, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: auth.isLoading
                        ? null
                        : () {
                            auth.clearError();
                            Navigator.pushNamed(
                              context,
                              Routes.registration,
                              arguments: widget.role,
                            );
                          },
                    child: Text(switch (widget.role) {
                      UserRole.citizen => 'Create Citizen Account',
                      UserRole.university => 'Register University',
                      UserRole.industry => 'Register Industry',
                      UserRole.admin => 'Request Admin Account',
                    }, style: TextStyle(color: role.primaryColor)),
                  ),
                  const SizedBox(height: 28),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            color: Color(0xFF6D7890),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Not a ${role.title}? ',
                          style: const TextStyle(color: Color(0xFF6D7890)),
                        ),
                        TextButton(
                          onPressed: auth.isLoading
                              ? null
                              : () => Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RoleSelectionScreen(),
                                  ),
                                  (_) => false,
                                ),
                          child: Text(
                            'Choose another role',
                            style: TextStyle(
                              color: role.primaryColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _subtitle => switch (widget.role) {
    UserRole.citizen => 'Welcome back! Continue making a difference.',
    UserRole.university => 'Collaborate on real-world challenges.',
    UserRole.industry => 'Partner with innovation and impact.',
    UserRole.admin => 'Secure access to the janYukti platform.',
  };
  Widget _emailInputs(AuthController auth, String label) => Column(
    children: [
      AuthTextField(
        label: label,
        hintText: 'Enter your ${label.toLowerCase()}',
        controller: identifier,
        prefixIcon: Icons.mail_outline,
        enabled: !auth.isLoading,
      ),
      const SizedBox(height: 18),
      AuthTextField(
        label: 'Password',
        hintText: 'Enter your password',
        controller: password,
        prefixIcon: Icons.lock_outline,
        obscureText: obscure,
        suffixIcon: obscure
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        onSuffixTap: () => setState(() => obscure = !obscure),
        enabled: !auth.isLoading,
      ),
    ],
  );
  Widget _error(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEFF0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message, style: const TextStyle(color: Color(0xFFC42B3B))),
      ),
    );
  }

  void _continueAuth(AuthController auth) {
    auth.loginWithEmail(context, widget.role, identifier.text, password.text);
  }

  Future<void> _resetPassword() async {
    final auth = ref.read(authControllerProvider);
    await auth.sendPasswordReset(identifier.text);
    if (mounted && auth.errorMessage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset link sent to your email.'),
        ),
      );
    }
  }
}
