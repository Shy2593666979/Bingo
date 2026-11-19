import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bingo/core/theme/app_theme.dart';

/// Shared materials for the neutral conversation scene with a blush accent.
abstract final class ChatScene {
  static Future<void> setNativeChrome(bool enabled) async {
    try {
      await const MethodChannel('bingo/device_tools')
          .invokeMethod<void>('setChatChrome', {'enabled': enabled});
    } on PlatformException catch (_) {
      // Desktop and older installations have no native page chrome.
    } on MissingPluginException catch (_) {}
  }

  static const ink = BingoPalette.ink;
  static const muted = BingoPalette.muted;
  static const accent = BingoPalette.sage;
  static const leaf = BingoPalette.userBubble;
  static const ivory = BingoPalette.surface;
}

class ChatGlass extends StatelessWidget {
  const ChatGlass({required this.child, this.bottom = false, super.key});
  final Widget child;
  final bool bottom;
  @override
  Widget build(BuildContext context) => ClipRect(
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
          child: DecoratedBox(
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .97),
                  border: Border(
                      bottom: bottom
                          ? BorderSide.none
                          : BorderSide(color: BingoPalette.line, width: .5))),
              child: child)));
}

class SageBubble extends StatelessWidget {
  const SageBubble(
      {required this.isUser,
      required this.child,
      this.tailAtTop = false,
      this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      super.key});
  final bool isUser;
  final Widget child;
  final EdgeInsets padding;
  final bool tailAtTop;
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _DefaultBubblePainter(isUser, tailAtTop),
      child: Padding(
          padding: EdgeInsets.fromLTRB(
              padding.left < 14 ? 14 : padding.left,
              padding.top,
              padding.right < 14 ? 14 : padding.right,
              padding.bottom),
          child: child));
}

/// A scalable outline and tail, kept independent of the text's layout.
class _DefaultBubblePainter extends CustomPainter {
  const _DefaultBubblePainter(this.isUser, this.tailAtTop);
  final bool isUser;
  final bool tailAtTop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (isUser) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final w = size.width, h = size.height;
    final r = (h / 2).clamp(0.0, 18.0);
    final path = Path()
      ..moveTo(5 + r, .5)
      ..lineTo(w - r, .5)
      ..quadraticBezierTo(w - .5, .5, w - .5, r)
      ..lineTo(w - .5, h - r)
      ..quadraticBezierTo(w - .5, h - .5, w - r, h - .5)
      ..lineTo(5 + r, h - .5);
    if (tailAtTop) {
      final tip = h / 2 < 18 ? h / 2 : 18.0;
      final belowTail = h - r < tip + 7 ? h - r : tip + 7;
      path
        ..quadraticBezierTo(5.5, h - .5, 5.5, h - r)
        ..lineTo(5.5, belowTail)
        ..quadraticBezierTo(5.5, tip + 3, .5, tip)
        ..quadraticBezierTo(5.5, tip - 1, 5.5, tip - 6)
        ..quadraticBezierTo(5.5, .5, 5 + r, .5)
        ..close();
    } else {
      path
        ..quadraticBezierTo(11, h - .5, 9, h - 3)
        ..quadraticBezierTo(5, h, .5, h - 1)
        ..quadraticBezierTo(6, h - 6, 5.5, h - 10)
        ..lineTo(5.5, r)
        ..quadraticBezierTo(5.5, .5, 5 + r, .5)
        ..close();
    }
    canvas.drawPath(
        path, Paint()..color = isUser ? BingoPalette.userBubble : Colors.white);
    canvas.drawPath(
        path,
        Paint()
          ..color =
              isUser ? BingoPalette.userBubbleBorder : const Color(0xFFD5D0D2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DefaultBubblePainter oldDelegate) =>
      oldDelegate.isUser != isUser || oldDelegate.tailAtTop != tailAtTop;
}
