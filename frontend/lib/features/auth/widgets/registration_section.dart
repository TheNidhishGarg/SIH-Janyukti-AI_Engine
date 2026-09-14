import 'package:flutter/material.dart';
import '../../../widgets/ui.dart';

class RegistrationSection extends StatelessWidget {
  const RegistrationSection({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      section(title),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 16), child: child),
          ],
        ),
      ),
    ],
  );
}
