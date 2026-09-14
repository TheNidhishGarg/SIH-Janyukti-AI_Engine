import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../core/localization/app_localizations.dart';

class RoleButton extends StatelessWidget {
  const RoleButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.isLoading = false,
  });
  final bool isLoading;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext c) => SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: isLoading ? null : onTap,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon ?? Icons.arrow_forward, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.color,
    required this.child,
    this.actions,
  });
  final String title;
  final Color color;
  final Widget child;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(
        tr(c, title),
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      actions: actions,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: child,
        ),
      ),
    ),
  );
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = 16,
    this.onTap,
  });
  final Widget child;
  final double padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext c) => Container(
    decoration: BoxDecoration(
      color: AppColors.body,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),

    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    ),
  );
}

class Stat extends StatelessWidget {
  const Stat(this.value, this.label, this.color, {super.key});
  final String value, label;
  final Color color;
  @override
  Widget build(BuildContext c) => Expanded(
    child: AppCard(
      padding: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 4,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            tr(c, label),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

Widget section(String s) => Builder(
  builder: (context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Text(
      tr(context, s),
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    ),
  ),
);

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext c) {
    final color = text.contains('Progress')
        ? AppColors.success
        : text.contains('High')
        ? AppColors.danger
        : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tr(c, text),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class Timeline extends StatelessWidget {
  const Timeline({
    super.key,
    required this.items,
    required this.active,
    required this.color,
  });

  final List<String> items;
  final int active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(items.length, (index) {
        final completed = index < active;

        final current = index == active;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Icon(
                  completed
                      ? Icons.check_circle_rounded
                      : current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: index <= active ? color : AppColors.line,
                  size: 22,
                ),

                if (index < items.length - 1)
                  Container(
                    width: 2,
                    height: 38,
                    color: index < active ? color : AppColors.line,
                  ),
              ],
            ),

            const SizedBox(width: 12),

            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    items[index],
                    style: TextStyle(
                      fontWeight: index <= active
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),

                  if (current)
                    Text(
                      'Current stage',
                      style: TextStyle(color: color, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
