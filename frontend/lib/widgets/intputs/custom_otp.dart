import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_dimensions.dart';

class CustomOtp extends StatelessWidget {
  final int length;
  final void Function(String)? onCompleted;

  const CustomOtp({
    super.key,
    this.length = 6, // Default OTP length is 6
    required this.onCompleted, // Callback to parent widget
  });
  @override
  Widget build(BuildContext context) {
    final defaultPinPutTheme = PinTheme(
      width: double.infinity,
      height: 56.0,
      decoration: BoxDecoration(
        color: AppColors.white100,
        shape: BoxShape.rectangle,
        borderRadius: AppDimensions.borderRadius,
        boxShadow: const <BoxShadow>[AppDimensions.otpShadow],
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
    );

    final focusedPinPutTheme = PinTheme(
      width: double.infinity,
      height: 56.0,
      decoration: BoxDecoration(
        color: AppColors.white100,
        shape: BoxShape.rectangle,
        borderRadius: AppDimensions.borderRadius,
        boxShadow: const <BoxShadow>[AppDimensions.otpShadow],
        border: Border.all(color: AppColors.primary, width: 1.0),
      ),
    );

    return SizedBox(
      width: double.infinity,
      height: 56.0,
      child: Pinput(
        length: length,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        onCompleted: onCompleted,
        defaultPinTheme: defaultPinPutTheme,
        focusedPinTheme: focusedPinPutTheme,
        submittedPinTheme: defaultPinPutTheme,
      ),
    );
  }
}
