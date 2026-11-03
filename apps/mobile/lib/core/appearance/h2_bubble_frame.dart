import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:bingo/core/appearance/illustrated_bubble_painter.dart';

/// The atlas remains intact. Nine native draw calls stretch only the blank
/// message region, preserving the illustrated corners for long replies.
class H2BubbleFrame extends StatelessWidget {
  const H2BubbleFrame(
      {required this.index,
      required this.child,
      required this.padding,
      this.compact = false,
      super.key});
  final int index;
  final Widget child;
  final EdgeInsets padding;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final background = Image.asset('assets/chat_bubbles/h2-atlas.webp',
        excludeFromSemantics: true,
        frameBuilder: (_, image, __, ___) =>
            image is RawImage && image.image != null
                ? CustomPaint(painter: _painter(image))
                : const SizedBox.shrink());
    if (compact) return AspectRatio(aspectRatio: 2.25, child: background);
    return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 96),
        child: Stack(children: [
          Positioned.fill(child: background),
          Padding(
              padding: EdgeInsets.fromLTRB(
                  math.max(23, padding.left),
                  math.max(index == 2 ? 22 : 16, padding.top),
                  math.max(index == 1 ? 26 : 23, padding.right),
                  math.max(17, padding.bottom)),
              child: child)
        ]));
  }

  CustomPainter _painter(RawImage raw) {
    final image = raw.image!;
    final w = image.width / 2, h = image.height / 3;
    final ox = (index % 2) * w, oy = (index ~/ 2) * h;
    final bounds = [
      const Rect.fromLTRB(33, 49, 750, 305),
      const Rect.fromLTRB(37, 46, 751, 317),
      const Rect.fromLTRB(28, 14, 740, 307),
      const Rect.fromLTRB(37, 42, 728, 300),
      const Rect.fromLTRB(34, 4, 743, 285),
      const Rect.fromLTRB(36, 18, 743, 286),
    ][index.clamp(0, 5)];
    return IllustratedBubblePainter(
        image: image,
        source: bounds.shift(Offset(ox, oy)),
        referenceWidth: compact ? 180 : 112);
  }
}
