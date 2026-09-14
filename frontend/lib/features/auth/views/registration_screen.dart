import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/registration_data.dart';
import '../../../models/user_role.dart';
import '../../../widgets/ui.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/registration_dropdown.dart';
import '../widgets/registration_section.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key, required this.role});
  final UserRole role;
  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in [
      'fullName',
      'email',
      'phone',
      'password',
      'confirmPassword',
      'city',
      'state',
      'designation',
      'organizationName',
      'website',
      'address',
    ])
      key: TextEditingController(),
  };
  String category = '';
  bool obscure = true;
  bool get organization =>
      widget.role == UserRole.university || widget.role == UserRole.industry;
  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget input(String key, String label, {bool required = false}) {
    final secret = key == 'password' || key == 'confirmPassword';
    return AuthTextField(
      label: '$label${required ? ' *' : ''}',
      hintText: label,
      controller: fields[key]!,
      prefixIcon: secret
          ? Icons.lock_outline
          : key == 'email'
          ? Icons.mail_outline
          : Icons.edit_outlined,
      keyboardType: key == 'email'
          ? TextInputType.emailAddress
          : key == 'phone'
          ? TextInputType.phone
          : TextInputType.text,
      obscureText: secret && obscure,
      suffixIcon: secret
          ? (obscure ? Icons.visibility_off : Icons.visibility)
          : null,
      onSuffixTap: () => setState(() => obscure = !obscure),
      enabled: !ref.watch(authControllerProvider).isLoading,
      validator: (v) {
        final value = v ?? '';
        if (required && value.trim().isEmpty) return '$label is required.';
        if (key == 'email' && !RegistrationData.validEmail(value)) {
          return 'Enter a valid email address.';
        }
        if (key == 'password' && value.length < 6) {
          return 'Use at least 6 characters.';
        }
        if (key == 'confirmPassword' && value != fields['password']!.text) {
          return 'Passwords must match.';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = getRoleConfig(widget.role);
    final auth = ref.watch(authControllerProvider);
    return PopScope(
      canPop: !auth.isLoading,
      child: PageFrame(
        title: 'Register ${config.title}',
        color: config.primaryColor,
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AuthHeader(
                icon: config.icon,
                title: '${config.title} Registration',
                subtitle: widget.role == UserRole.citizen
                    ? 'Join janYukti and make a difference.'
                    : 'Submit your details for administrator approval.',
                color: config.primaryColor,
              ),
              if (organization)
                RegistrationSection(
                  title: 'Organization details',
                  children: [
                    input(
                      'organizationName',
                      widget.role == UserRole.university
                          ? 'University Name'
                          : 'Company / Organization Name',
                      required: true,
                    ),
                    RegistrationDropdown(
                      label: widget.role == UserRole.university
                          ? 'University Type *'
                          : 'Industry Sector *',
                      enabled: !auth.isLoading,
                      items: widget.role == UserRole.university
                          ? const [
                              'Central University',
                              'State University',
                              'Private University',
                              'Deemed University',
                              'Institute / College',
                              'Other',
                            ]
                          : const [
                              'Information Technology',
                              'Healthcare',
                              'Agriculture',
                              'Manufacturing',
                              'Energy',
                              'Education',
                              'Transportation',
                              'Finance',
                              'Environment',
                              'Construction',
                              'Other',
                            ],
                      onChanged: (v) => category = v ?? '',
                    ),
                    input('website', 'Website'),
                    input('address', 'Address', required: true),
                  ],
                ),
              RegistrationSection(
                title: organization ? 'Contact person' : 'Personal details',
                children: [
                  input(
                    'fullName',
                    organization ? 'Contact Person Name' : 'Full Name',
                    required: true,
                  ),
                  if (widget.role != UserRole.citizen)
                    input(
                      'designation',
                      widget.role == UserRole.admin
                          ? 'Department / Designation'
                          : 'Contact Person Designation',
                      required: true,
                    ),
                  input('phone', 'Phone Number', required: organization),
                  if (widget.role != UserRole.admin) ...[
                    input('city', 'City', required: organization),
                    input('state', 'State', required: organization),
                  ],
                ],
              ),
              RegistrationSection(
                title: 'Account details',
                children: [
                  input(
                    'email',
                    widget.role == UserRole.citizen
                        ? 'Email Address'
                        : 'Official Email',
                    required: true,
                  ),
                  input('password', 'Password', required: true),
                  input('confirmPassword', 'Confirm Password', required: true),
                ],
              ),
              if (auth.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    auth.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: config.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: auth.isLoading
                      ? null
                      : () {
                          if (!form.currentState!.validate()) return;
                          auth.register(
                            context,
                            RegistrationData(
                              role: widget.role,
                              fullName: fields['fullName']!.text,
                              email: fields['email']!.text,
                              password: fields['password']!.text,
                              confirmPassword: fields['confirmPassword']!.text,
                              phone: fields['phone']!.text,
                              city: fields['city']!.text,
                              state: fields['state']!.text,
                              designation: fields['designation']!.text,
                              organizationName:
                                  fields['organizationName']!.text,
                              category: category,
                              website: fields['website']!.text,
                              address: fields['address']!.text,
                            ),
                          );
                        },
                  child: auth.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit Registration'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
