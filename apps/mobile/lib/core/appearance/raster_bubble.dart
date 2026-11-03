import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:bingo/core/appearance/bubble_source_bounds.dart';
import 'package:bingo/core/appearance/illustrated_bubble_painter.dart';

class RasterBubbleFrame extends StatelessWidget {
  const RasterBubbleFrame(
      {required this.asset,
      required this.sourceSize,
      required this.child,
      required this.fallback,
      this.compact = false,
      this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      super.key});
  final String asset;
  final Size sourceSize;
  final Widget child;
  final Color fallback;
  final bool compact;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Image.asset(asset,
          fit: BoxFit.contain,
          cacheWidth: 480,
          errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    final name = asset.split('/').last.split('.').first;
    final crop = bubbleSourceBounds[name] ?? const Rect.fromLTRB(0, 0, 1, 1);
    // Reserve actual ornaments instead of applying 29px to every edge.
    final safe = switch (name) {
      'qiqi' => const EdgeInsets.fromLTRB(25, 15, 19, 12),
      'truck-v2' => const EdgeInsets.fromLTRB(38, 12, 14, 22),
      'pot-v2' => const EdgeInsets.fromLTRB(22, 24, 22, 20),
      'nian' || 'shiba' => const EdgeInsets.fromLTRB(23, 22, 22, 14),
      'ginger' || 'wolf' => const EdgeInsets.fromLTRB(23, 20, 22, 12),
      _ => const EdgeInsets.fromLTRB(22, 16, 22, 14),
    };
    final insets = EdgeInsets.fromLTRB(
        math.max(safe.left, padding.left),
        math.max(safe.top, padding.top),
        math.max(safe.right, padding.right),
        math.max(safe.bottom, padding.bottom));
    return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 96),
        child: Stack(fit: StackFit.passthrough, children: [
          Positioned.fill(
              child: Image.asset(asset,
                  cacheWidth: math.min(960, sourceSize.width).round(),
                  excludeFromSemantics: true,
                  frameBuilder: (_, child, __, ___) {
                    if (child is! RawImage || child.image == null) {
                      return const SizedBox.shrink();
                    }
                    final image = child.image!;
                    return CustomPaint(
                        painter: IllustratedBubblePainter(
                            image: image,
                            source: Rect.fromLTRB(
                                crop.left * image.width,
                                crop.top * image.height,
                                crop.right * image.width,
                                crop.bottom * image.height),
                            referenceWidth: 112,
                            stretchX: name == 'truck-v2' ? .60 : .50,
                            stretchY: name == 'pot-v2' ? .57 : .46));
                  },
                  errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                          color: fallback,
                          borderRadius: BorderRadius.circular(16))))),
          Padding(padding: insets, child: child),
        ]));
  }
}
