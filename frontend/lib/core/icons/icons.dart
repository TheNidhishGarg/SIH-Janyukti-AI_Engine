  import 'package:flutter/material.dart';
  import 'package:flutter_svg/flutter_svg.dart';

  import 'icons_path.dart';

  class CustomIcon extends StatelessWidget {
    final String name;
    final double? size;
    final Color? color;
    final Color? hoverColor;
    final BackgroundOptions? background;
    final bool noHover;
    final String? title;
    final bool disabled;
    final VoidCallback? onClick;

    const CustomIcon({
      super.key,
      required this.name,
      this.size = 24.0,
      this.color,
      this.hoverColor,
      this.background,
      this.noHover = false,
      this.title,
      this.disabled = false,
      this.onClick,
    });

    @override
    Widget build(BuildContext context) {
      // Ensure the icon exists
      final iconData = IconPaths.paths[name];
      if (iconData == null) {
        throw Exception('$name is not a valid icon name.');
      }

      // Build the SVG icon
      Widget iconWidget = SvgPicture.string(
        iconData.path,
        height: size,
        width: size,
        colorFilter: disabled || color != null
            ? ColorFilter.mode(disabled ? Colors.grey : color!, BlendMode.srcIn)
            : null,
        placeholderBuilder: (context) => const CircularProgressIndicator(),
      );

      // Add hover effect (only works on web/desktop)
      if (!noHover && hoverColor != null) {
        iconWidget = MouseRegion(
          onEnter: (_) {},
          onExit: (_) {},
          child: iconWidget,
        );
      }

      // Wrap with background if provided
      if (background != null) {
        return GestureDetector(
          onTap: disabled ? null : onClick,
          child: Container(
            width: background!.size ?? size! + (background!.padding ?? 10),
            height: background!.size ?? size! + (background!.padding ?? 10),
            decoration: BoxDecoration(
              color: background!.color,
              border: background!.borderColor != null
                  ? Border.all(color: background!.borderColor!)
                  : null,
              borderRadius: background!.type == BackgroundType.rounded
                  ? BorderRadius.circular(100)
                  : BorderRadius.circular(4),
              boxShadow: background!.elevated
                  ? [const BoxShadow(color: Colors.black12, blurRadius: 6)]
                  : null,
            ),
            child: Center(child: iconWidget),
          ),
        );
      }

      // Default icon with optional title for accessibility
      return GestureDetector(
        onTap: disabled ? null : onClick,
        child: title != null
            ? Semantics(
                label: title,
                child: iconWidget,
              )
            : iconWidget,
      );
    }
  }

  // Background options class
  class BackgroundOptions {
    final BackgroundType type;
    final Color color;
    final Color? borderColor;
    final double? padding;
    final double? size;
    final bool elevated;

    BackgroundOptions({
      required this.type,
      required this.color,
      this.borderColor,
      this.padding,
      this.size,
      this.elevated = false,
    });
  }

  enum BackgroundType { rounded, box }
