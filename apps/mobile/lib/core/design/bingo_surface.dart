import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Quiet, bordered surfaces used by profile and creation screens.
class BingoSurface extends StatelessWidget {
  const BingoSurface(
      {required this.child,
      this.padding = const EdgeInsets.all(16),
      this.onTap,
      this.radius = 14,
      super.key});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: const BorderSide(color: BingoPalette.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class BingoSectionTitle extends StatelessWidget {
  const BingoSectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: BingoPalette.ink));
}
