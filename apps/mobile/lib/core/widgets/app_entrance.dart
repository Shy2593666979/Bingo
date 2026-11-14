import 'package:flutter/material.dart';

/// Mounts the page immediately; the visual entrance never delays its requests.
class AppEntrance extends StatelessWidget {
  const AppEntrance({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: child,
        builder: (context, progress, child) => Opacity(
            opacity: progress,
            child: Transform.translate(
                offset: Offset(0, 6 * (1 - progress)), child: child)));
  }
}
