import 'package:flutter/material.dart';
import 'package:bingo/core/role_avatar_assets.dart';

/// Shared soft square silhouette for people, companions and group covers.
class AvatarFrame extends StatelessWidget {
  const AvatarFrame(
      {required this.size,
      required this.child,
      this.color = const Color(0xFFE8F8F2),
      this.cornerRadius,
      super.key});
  final double size;
  final Widget child;
  final Color color;
  final double? cornerRadius;
  static BorderRadius radius(double size) => BorderRadius.circular(size * .24);
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: ClipRSuperellipse(
          borderRadius: cornerRadius == null
              ? radius(size)
              : BorderRadius.circular(cornerRadius!),
          child: ColoredBox(color: color, child: child)));
}

/// Keep saved legacy asset names compatible while rendering the new portraits.
String squareAvatarAsset(String asset) {
  final filename = asset.split('/').last;
  if (roleAvatarFiles.contains(filename)) {
    if (filename == 'bingo_logo.png') return 'assets/images/bingo_logo.webp';
    return 'assets/avatars_square/${filename.replaceFirst('.png', '.webp')}';
  }
  return asset;
}

class ChatPortrait extends StatelessWidget {
  const ChatPortrait({required this.size, required this.child, super.key});
  final double size;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: child);
}
