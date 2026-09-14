import 'user_role.dart';

class RegistrationData {
  const RegistrationData({
    required this.role,
    required this.fullName,
    required this.email,
    required this.password,
    required this.confirmPassword,
    this.phone = '',
    this.city = '',
    this.state = '',
    this.designation = '',
    this.organizationName = '',
    this.category = '',
    this.website = '',
    this.address = '',
  });
  final UserRole role;
  final String fullName,
      email,
      password,
      confirmPassword,
      phone,
      city,
      state,
      designation,
      organizationName,
      category,
      website,
      address;
  bool get isOrganization =>
      role == UserRole.university || role == UserRole.industry;
  static bool validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
  String? validate() {
    if (fullName.trim().isEmpty) return 'Full name is required.';
    if (!validEmail(email)) return 'Enter a valid email address.';
    if (password.length < 6) {
      return 'Password must contain at least 6 characters.';
    }
    if (password != confirmPassword) return 'Passwords must match.';
    if (role != UserRole.citizen && designation.trim().isEmpty) {
      return 'Designation is required.';
    }
    if (isOrganization &&
        [
          organizationName,
          category,
          phone,
          address,
          city,
          state,
        ].any((v) => v.trim().isEmpty)) {
      return 'Complete all required organization fields.';
    }
    if (website.trim().isNotEmpty) {
      final uri = Uri.tryParse(website.trim());
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        return 'Enter a website beginning with https:// or http://.';
      }
    }
    return null;
  }
}
