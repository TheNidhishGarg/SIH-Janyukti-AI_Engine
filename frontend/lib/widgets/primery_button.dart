import 'package:flutter/material.dart';

import '../core/icons/icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import 'loader.dart';

class CustomPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double? width;
  final Color? backgroundColor;
  final String? icon;
  final bool showIconInRight;
  final bool isFullWidth;
  final bool isLoading;

  const CustomPrimaryButton({
    super.key,
    required this.onTap,
    required this.label,
    this.width,
    this.backgroundColor = AppColors.solidDarkBg,
    this.icon,
    this.showIconInRight = true,
    this.isFullWidth = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onTap,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.solidDarkBgDisabled;
          }
          return backgroundColor!;
        }),
        overlayColor: WidgetStateProperty.all(AppColors.solidDarkHover),
        shape: WidgetStateProperty.all(
          const RoundedRectangleBorder(
            borderRadius: AppDimensions.borderRadius8,
          ),
        ),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.solidDarkPlaceholderDisabled;
          }
          return AppColors.solidDarkPlaceholder;
        }),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        width: isFullWidth ? double.infinity : width,
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: isLoading
              ? const Loader(size: 18, color: AppColors.solidDarkPlaceholder)
              : Row(
                  key: const ValueKey('content'),
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null && !showIconInRight) ...[
                      CustomIcon(
                        name: icon!,
                        color: onTap == null
                            ? AppColors.solidDarkIconDisabled
                            : AppColors.solidDarkIcon,
                        size: 14,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        letterSpacing: 0.5,
                        color: onTap == null
                            ? AppColors.solidDarkPlaceholderDisabled
                            : AppColors.solidDarkPlaceholder,
                      ),
                    ),
                    if (icon != null && showIconInRight) ...[
                      const SizedBox(width: 10),
                      CustomIcon(
                        name: icon!,
                        color: onTap == null
                            ? AppColors.solidDarkIconDisabled
                            : AppColors.solidDarkIcon,
                        size: 14,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
