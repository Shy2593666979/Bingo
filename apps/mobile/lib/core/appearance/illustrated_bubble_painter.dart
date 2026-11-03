import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Source-space cropping removes empty gutters. Only the blank centre grows;
/// corner illustrations keep the same size for short and long messages.
class IllustratedBubblePainter extends CustomPainter {
  const IllustratedBubblePainter(
      {required this.image,
      required this.source,
      required this.referenceWidth,
      this.stretchX = .50,
      this.stretchY = .46});
  final ui.Image image;
  final Rect source;
  final double referenceWidth, stretchX, stretchY;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.min(referenceWidth / source.width,
        math.min(size.width / source.width, size.height / source.height));
    final cx = source.left + source.width * stretchX;
    final cy = source.top + source.height * stretchY;
    final sx = [source.left, cx - .5, cx + .5, source.right];
    final sy = [source.top, cy - .5, cy + .5, source.bottom];
    final dx = [
      0.0,
      (sx[1] - sx[0]) * scale,
      size.width - (sx[3] - sx[2]) * scale,
      size.width
    ];
    final dy = [
      0.0,
      (sy[1] - sy[0]) * scale,
      size.height - (sy[3] - sy[2]) * scale,
      size.height
    ];
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        canvas.drawImageRect(
            image,
            Rect.fromLTRB(sx[x], sy[y], sx[x + 1], sy[y + 1]),
            Rect.fromLTRB(dx[x], dy[y], dx[x + 1], dy[y + 1]),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(IllustratedBubblePainter old) =>
      image != old.image ||
      source != old.source ||
      referenceWidth != old.referenceWidth ||
      stretchX != old.stretchX ||
      stretchY != old.stretchY;
}
