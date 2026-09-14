import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class ErrorText extends StatelessWidget {
  final String error;
  const ErrorText({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Text(
      error,
      style: TextStyle(color: AppColors.red600, fontWeight: FontWeight.bold),
    );
  }
}
