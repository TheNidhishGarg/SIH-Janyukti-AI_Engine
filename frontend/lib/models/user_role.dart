import 'package:flutter/material.dart';

enum UserRole { citizen, university, industry, admin }

extension UserRoleX on UserRole {
  String get storageKey => name;
  static UserRole? fromStorageKey(String? value) => switch (value) {
    'citizen' => UserRole.citizen,
    'university' => UserRole.university,
    'industry' => UserRole.industry,
    'admin' => UserRole.admin,
    _ => null,
  };
}

class RoleConfig {
  const RoleConfig({
    required this.title,
    required this.subtitle,
    required this.loginLabel,
    required this.primaryColor,
    required this.icon,
    required this.emailLabel,
  });
  final String title, subtitle, loginLabel, emailLabel;
  final Color primaryColor;
  final IconData icon;
}

RoleConfig getRoleConfig(UserRole role) => switch (role) {
  UserRole.citizen => const RoleConfig(
    title: 'Citizen',
    subtitle: 'Report and track public issues',
    loginLabel: 'Login as Citizen',
    emailLabel: 'Email Address',
    primaryColor: Color(0xFF218C4A),
    icon: Icons.person_outline,
  ),
  UserRole.university => const RoleConfig(
    title: 'University',
    subtitle: 'Solve real-world challenges',
    loginLabel: 'Login as University',
    emailLabel: 'Institution Email',
    primaryColor: Color(0xFF6541A5),
    icon: Icons.school_outlined,
  ),
  UserRole.industry => const RoleConfig(
    title: 'Industry',
    subtitle: 'Collaborate and provide solutions',
    loginLabel: 'Login as Industry',
    emailLabel: 'Business Email',
    primaryColor: Color(0xFFF97316),
    icon: Icons.business_outlined,
  ),
  UserRole.admin => const RoleConfig(
    title: 'Admin',
    subtitle: 'Manage the janYukti ecosystem',
    loginLabel: 'Login as Admin',
    emailLabel: 'Email Address',
    primaryColor: Color(0xFF2563EB),
    icon: Icons.admin_panel_settings_outlined,
  ),
};
