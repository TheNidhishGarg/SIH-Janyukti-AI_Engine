import 'package:flutter/material.dart';

import '../../../models/challenge_model.dart';
import '../../../widgets/ui.dart';
import '../../../theme/app_colors.dart';

class ChallengeCard extends StatelessWidget {
  const ChallengeCard(this.x, {super.key, this.onTap});
  final Challenge x;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext c) => AppCard(
    onTap: onTap,
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: Color(0xFFEAF7EF),
          child: Icon(Icons.water_drop, color: AppColors.citizen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                x.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                x.location,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        StatusPill(x.status),
      ],
    ),
  );
}
