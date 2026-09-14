import 'package:flutter/material.dart';

class RegistrationDropdown extends StatelessWidget {
  const RegistrationDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });
  final String label;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: items
        .map(
          (s) => DropdownMenuItem(
            value: s,
            child: Text(s, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: enabled ? onChanged : null,
    validator: (value) => value == null ? 'Please select an option.' : null,
  );
}
