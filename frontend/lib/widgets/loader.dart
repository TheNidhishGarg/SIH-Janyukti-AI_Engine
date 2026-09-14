import 'package:flutter/material.dart';

import '../core/icons/icons.dart';

class Loader extends StatefulWidget {
  final double size;
  final Color? color;
  const Loader({super.key, this.size = 50, this.color});

  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Initialize the animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(); // Repeats the animation indefinitely
  }

  @override
  void dispose() {
    _controller
        .dispose(); // Dispose of the controller when the widget is removed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller, // Bind the controller to the rotation animation
      child: Center(
        child: CustomIcon(
          name: 'loader',
          size: widget.size,
          color: widget.color,
        ),
      ),
    );
  }
}
