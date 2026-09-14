import 'package:flutter/material.dart';

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.controller,
    required this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.onSuffixTap,
    this.enabled = true,
    this.validator,
    this.keyboardType,
  });
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final String label, hintText;
  final TextEditingController controller;
  final IconData prefixIcon;
  final bool obscureText, enabled;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  @override
  Widget build(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      TextFormField(
        validator: validator,
        keyboardType: keyboardType,
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(prefixIcon),
          suffixIcon: suffixIcon == null
              ? null
              : IconButton(onPressed: onSuffixTap, icon: Icon(suffixIcon)),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 17,
            horizontal: 14,
          ),
        ),
      ),
    ],
  );
}
