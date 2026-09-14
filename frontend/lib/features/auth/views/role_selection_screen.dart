import 'package:flutter/material.dart';
import '../../../models/user_role.dart';
import '../../../theme/app_colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../widgets/role_card.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 36, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(child: Image.asset('assets/janyukti.png', height: 80)),
                const SizedBox(height: 12),
                Text(
                  tr(c, 'Welcome to janYukti'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.title,
                  ),
                ),
                const SizedBox(height: 4),

                Text(
                  tr(c, 'Choose how you want to continue'),
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 30),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButtonFormField<AppLanguage>(
                    initialValue: LanguageScope.of(c).language,
                    decoration: const InputDecoration(
                      labelText: 'Language / भाषा',
                      prefixIcon: Icon(Icons.language_outlined),
                    ),
                    items: AppLanguage.values
                        .map(
                          (language) => DropdownMenuItem(
                            value: language,
                            child: Text(languageName(language)),
                          ),
                        )
                        .toList(),
                    onChanged: (language) {
                      if (language != null) {
                        LanguageScope.of(c).select(language);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 20),
                for (final role in UserRole.values)
                  RoleCard(
                    title: tr(c, getRoleConfig(role).title),
                    description: tr(c, getRoleConfig(role).subtitle),
                    icon: getRoleConfig(role).icon,
                    color: getRoleConfig(role).primaryColor,
                    onTap: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                        builder: (_) => LoginScreen(role: role),
                      ),
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
