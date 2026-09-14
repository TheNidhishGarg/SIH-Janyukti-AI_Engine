import 'package:flutter/material.dart';

import '../../../theme/app_dimensions.dart';

class RoleCard extends StatelessWidget {
  const RoleCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),

        boxShadow: [AppDimensions.primaryShadow],
      ),

      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),

        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),

          splashColor: color.withValues(alpha: 0.08),
          highlightColor: color.withValues(alpha: 0.03),

          child: Container(
            padding: const EdgeInsets.all(18),

            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),

              border: Border.all(color: color.withValues(alpha: 0.12)),
            ),

            child: Row(
              children: [
                // Role Icon
                Container(
                  width: 58,
                  height: 58,

                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),

                  child: Icon(icon, color: color, size: 28),
                ),

                const SizedBox(width: 16),

                // Text Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: Color(0xFF182230),
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: Color(0xFF748094),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Modern Arrow Button
                Container(
                  width: 36,
                  height: 36,

                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),

                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: color,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
