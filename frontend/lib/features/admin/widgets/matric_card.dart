import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, 
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
    this.highlighted = false,
  });

  final int count;
  final String label;
  final IconData icon;
  final Color color;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: highlighted
            ? color.withOpacity(.045)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted
              ? color.withOpacity(.20)
              : const Color(0xFFE3E8F1),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF344054)
                .withOpacity(.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 27,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 25,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: highlighted
                        ? color
                        : const Color(0xFF101B42),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF596579),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}