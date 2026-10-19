import 'package:flutter/material.dart';

class AnimatedPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const AnimatedPress({super.key, required this.child, this.onTap});

  @override
  State<AnimatedPress> createState() => _AnimatedPressState();
}

class _AnimatedPressState extends State<AnimatedPress> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) => setState(() => _scale = 0.95);
  void _onTapUp(TapUpDetails details) => setState(() => _scale = 1.0);
  void _onTapCancel() => setState(() => _scale = 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : _onTapDown,
      onTapUp: widget.onTap == null ? null : _onTapUp,
      onTapCancel: widget.onTap == null ? null : _onTapCancel,
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AbsorbPointer(
          child: widget.child,
        ),
      ),
    );
  }
}