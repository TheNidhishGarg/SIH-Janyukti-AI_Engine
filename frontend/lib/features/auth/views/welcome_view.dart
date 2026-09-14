import 'package:flutter/material.dart';
import '../../../widgets/primery_button.dart';
import '../../../core/routes/app_routes.dart';
import '../../../theme/app_colors.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              spacing: 12,
              children: [
                Image.asset('assets/janyukti.png', height: 120),
                const Text(
                  'Together, we solve tomorrow’s challenges today.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: AppColors.muted),
                ),
              ],
            ),
            Image.asset('assets/puzzle.png'),
            CustomPrimaryButton(
              label: 'Get Started',
              onTap: () => Navigator.pushNamed(c, Routes.roleSelection),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}
