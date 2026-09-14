import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, 
    required this.title,
    this.onViewAll,
  });

  final String title;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF101B42),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -.3,
            ),
          ),
        ),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
              ),
            ),
            child: Row(
              children: [
                Text(
                  'View All',
                  style: TextStyle(
                    color: AppColors.admin,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: AppColors.admin,
                ),
              ],
            ),
          ),
      ],
    );
  }
}