import 'package:flutter/material.dart';

class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
  final IconData icon;
  final String title, subtitle;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .12),
        ),
        child: Icon(icon, size: 42, color: color),
      ),
      const SizedBox(height: 20),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: Color(0xFF122044),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF6D7890), height: 1.4),
      ),
    ],
  );
}
