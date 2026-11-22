import 'package:flutter/material.dart';

/// Shared A-variant mascot used by authentication and startup screens.
/// Retains the public widget name so existing callers share the same branding.
class BingoWordmark extends StatelessWidget {
  const BingoWordmark({required this.width, required this.height, super.key});
  static const asset = AssetImage('assets/images/bingo_logo_foreground.webp');
  final double width, height;
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Bingo',
      image: true,
      child: Image(
          image: asset,
          width: width,
          height: height,
          fit: BoxFit.contain,
          gaplessPlayback: true));
}
