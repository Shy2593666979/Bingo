import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Vector artwork keeps the corners crisp while the message body grows.
/// Decorations sit in reserved margins; text is never painted over.
class BubbleArtworkPainter extends CustomPainter {
  const BubbleArtworkPainter(
      {required this.id,
      required this.isUser,
      required this.fill,
      required this.accent,
      required this.radius,
      this.compact = false});
  final String id;
  final bool isUser, compact;
  final Color fill, accent;
  final BorderRadius radius;

  double get top => compact ? 14 : 24;
  double get bottom => compact ? 6 : 11;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(4, top, size.width - 4, size.height - bottom);
    if (rect.width <= 0 || rect.height <= 0) return;
    final body = radius.toRRect(rect);
    final outline = accent.withValues(alpha: id == 'comic' ? 1 : .30);
    final glass = id == 'jelly' || id == 'ocean';
    final paper = id == 'paper' || id == 'peach';
    canvas.drawRRect(
        body.shift(id == 'comic' ? const Offset(3, 3) : const Offset(0, 3)),
        Paint()
          ..color = id == 'comic' ? accent : accent.withValues(alpha: .09)
          ..maskFilter = id == 'comic'
              ? null
              : const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: glass
                ? [
                    Color.lerp(fill, Colors.white, .80)!,
                    Color.lerp(fill, Colors.white, .12)!,
                    fill,
                    Color.lerp(fill, accent, .08)!
                  ]
                : [Color.lerp(fill, Colors.white, paper ? .12 : .45)!, fill],
            stops: glass ? const [0, .38, .70, 1] : null,
          ).createShader(rect));
    canvas.drawRRect(
        body,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = id == 'comic' ? 1.6 : 1.1);

    final inset = rect.deflate(3);
    if (glass) {
      canvas.drawRRect(
          radius.toRRect(inset),
          Paint()
            ..color = Colors.white.withValues(alpha: .82)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
      canvas.save();
      canvas.clipRRect(body);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(rect.left + 10, rect.top + 5,
                  math.max(12, rect.width - 25), compact ? 5 : 9),
              const Radius.circular(9)),
          Paint()
            ..shader = LinearGradient(colors: [
              Colors.white.withValues(alpha: .95),
              Colors.white.withValues(alpha: 0)
            ]).createShader(rect));
      canvas.drawArc(
          Rect.fromLTWH(
              rect.right - 12, rect.top + 8, 6, math.max(4, rect.height - 16)),
          -.65,
          1.2,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: .75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round);
      canvas.restore();
      if (!compact) {
        _sparkle(
            canvas,
            Offset(isUser ? rect.left + 7 : rect.right - 6, rect.bottom - 2),
            6,
            Colors.white,
            accent.withValues(alpha: .45));
      }
    }
    if (id == 'ribbon' || id == 'rose') {
      _lace(canvas, inset);
      _bow(
          canvas,
          Offset(isUser ? rect.right - 25 : rect.left + 25, rect.top + 1),
          compact ? .58 : 1,
          fill);
      if (!compact) {
        _heart(
            canvas,
            Offset(isUser ? rect.left + 13 : rect.right - 13, rect.bottom),
            5,
            Color.lerp(fill, accent, .25)!);
      }
    } else if (id == 'rabbit') {
      final x = isUser ? rect.right - 33 : rect.left + 33;
      _ear(canvas, Offset(x - 8, rect.top + 1), compact ? .6 : 1, -.22, true);
      _ear(canvas, Offset(x + 8, rect.top + 1), compact ? .6 : 1, .20, true);
      _paw(
          canvas,
          Offset(isUser ? rect.left + 12 : rect.right - 12, rect.bottom - 1),
          compact ? .55 : .8);
      if (!compact) {
        _heart(
            canvas,
            Offset(isUser ? rect.right - 10 : rect.left + 10, rect.bottom - 3),
            4,
            const Color(0xFFEFA5B4));
      }
    } else if (id == 'kitty') {
      final x = isUser ? rect.right - 28 : rect.left + 28;
      _ear(
          canvas, Offset(x - 10, rect.top + 2), compact ? .65 : 1, -.15, false);
      _ear(canvas, Offset(x + 10, rect.top + 2), compact ? .65 : 1, .15, false);
      _paw(
          canvas,
          Offset(isUser ? rect.left + 14 : rect.right - 14, rect.bottom - 1),
          compact ? .55 : .85);
      if (!compact) {
        final c =
            Offset(isUser ? rect.right - 14 : rect.left + 14, rect.bottom - 4);
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
              c + Offset(-6, (i - 1) * 3),
              c + Offset(-12, (i - 1) * 5),
              Paint()
                ..color = accent.withValues(alpha: .45)
                ..strokeWidth = 1
                ..strokeCap = StrokeCap.round);
        }
      }
    } else if (paper) {
      // A second paper edge, stitched inset and translucent washi tape.
      final stitch = Paint()
        ..color = accent.withValues(alpha: .32)
        ..strokeWidth = .8
        ..strokeCap = StrokeCap.round;
      for (double x = rect.left + 11; x < rect.right - 9; x += 6) {
        canvas.drawLine(Offset(x, rect.bottom - 5),
            Offset(x + 2.4, rect.bottom - 5), stitch);
      }
      _tape(canvas, Offset(isUser ? rect.right - 24 : rect.left + 24, rect.top),
          compact ? .65 : 1, isUser ? .16 : -.15);
      if (!compact) {
        canvas.drawLine(
            Offset(rect.left + 8, rect.bottom + 2),
            Offset(rect.right - 8, rect.bottom + 2),
            Paint()
              ..color = accent.withValues(alpha: .14)
              ..strokeWidth = 1);
        _heart(
            canvas,
            Offset(isUser ? rect.left + 12 : rect.right - 12, rect.bottom - 1),
            5,
            accent.withValues(alpha: .48));
      }
    } else if (id == 'violet') {
      final x = isUser ? rect.right - 20 : rect.left + 20;
      canvas.drawLine(
          Offset(x, rect.top - 11),
          Offset(x, rect.top + 5),
          Paint()
            ..color = accent.withValues(alpha: .5)
            ..strokeWidth = 1);
      _sparkle(canvas, Offset(x, rect.top + 5), compact ? 4 : 7,
          const Color(0xFFFFE9A9), accent.withValues(alpha: .6));
      if (!compact) {
        _sparkle(
            canvas,
            Offset(isUser ? rect.left + 9 : rect.right - 9, rect.bottom - 1),
            5,
            const Color(0xFFFFF3CF),
            accent.withValues(alpha: .45));
        canvas.drawCircle(
            Offset(x + 11, rect.top - 3), 1.6, Paint()..color = Colors.white);
      }
    } else if (id == 'comic' && !compact) {
      _sparkle(
          canvas,
          Offset(isUser ? rect.right - 12 : rect.left + 12, rect.top),
          6,
          const Color(0xFFFFE899),
          accent);
    }
  }

  void _ear(
      Canvas canvas, Offset base, double scale, double rotation, bool rabbit) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(rotation);
    canvas.scale(scale);
    final ear = rabbit
        ? (Path()
          ..moveTo(-6, 2)
          ..cubicTo(-11, -26, 7, -29, 6, 2)
          ..close())
        : (Path()
          ..moveTo(-8, 2)
          ..lineTo(-7, -15)
          ..quadraticBezierTo(-6, -19, -3, -15)
          ..lineTo(8, 2)
          ..close());
    canvas.drawPath(ear, Paint()..color = const Color(0xFFFFFCF6));
    canvas.drawPath(
        ear,
        Paint()
          ..color = accent.withValues(alpha: .45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1);
    final inner = rabbit
        ? Rect.fromLTWH(-2.2, -16, 4.4, 13)
        : Rect.fromLTWH(-4, -10, 4, 8);
    canvas.drawRRect(RRect.fromRectAndRadius(inner, const Radius.circular(4)),
        Paint()..color = const Color(0xFFF3C1CC));
    canvas.restore();
  }

  void _paw(Canvas canvas, Offset center, double scale) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    final shape = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-10, -10, 20, 19), const Radius.circular(9));
    canvas.drawRRect(shape, Paint()..color = const Color(0xFFFFFCF8));
    canvas.drawRRect(
        shape,
        Paint()
          ..color = accent.withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    final pink = Paint()..color = const Color(0xFFEAB4C1);
    canvas.drawOval(const Rect.fromLTWH(-4, -1, 8, 6), pink);
    for (final x in [-5.0, 0.0, 5.0]) {
      canvas.drawOval(
          Rect.fromCenter(center: Offset(x, -4), width: 3.2, height: 4), pink);
    }
    canvas.restore();
  }

  void _bow(Canvas canvas, Offset center, double scale, Color base) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    final ribbon = Color.lerp(base, accent, .24)!;
    final border = accent.withValues(alpha: .5);
    final tails = Path()
      ..moveTo(-3, 2)
      ..lineTo(-12, 17)
      ..lineTo(-5, 15)
      ..lineTo(-1, 19)
      ..lineTo(3, 3)
      ..moveTo(2, 2)
      ..lineTo(11, 17)
      ..lineTo(15, 12)
      ..lineTo(20, 12)
      ..lineTo(6, 0);
    canvas.drawPath(tails, Paint()..color = ribbon);
    final wings = Path()
      ..moveTo(0, 0)
      ..cubicTo(-8, -14, -24, -15, -21, -3)
      ..cubicTo(-23, 10, -9, 9, 0, 2)
      ..moveTo(0, 0)
      ..cubicTo(8, -14, 24, -15, 21, -3)
      ..cubicTo(23, 10, 9, 9, 0, 2);
    canvas.drawPath(
        wings,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, ribbon])
              .createShader(const Rect.fromLTWH(-23, -13, 46, 26)));
    canvas.drawPath(
        wings,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    for (final side in [-1.0, 1.0]) {
      canvas.drawLine(
          Offset(side * 3, 0),
          Offset(side * 15, -4),
          Paint()
            ..color = Colors.white.withValues(alpha: .8)
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-4, -5, 8, 11), const Radius.circular(3)),
        Paint()..color = ribbon);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-4, -5, 8, 11), const Radius.circular(3)),
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8);
    canvas.restore();
  }

  void _lace(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = accent.withValues(alpha: .28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    for (double x = rect.left + 16; x < rect.right - 12; x += 8) {
      canvas.drawArc(
          Rect.fromCenter(center: Offset(x, rect.top + 1), width: 7, height: 7),
          0,
          math.pi,
          false,
          paint);
      canvas.drawArc(
          Rect.fromCenter(
              center: Offset(x, rect.bottom - 1), width: 7, height: 7),
          math.pi,
          math.pi,
          false,
          paint);
    }
    for (double y = rect.top + 17; y < rect.bottom - 12; y += 8) {
      canvas.drawCircle(Offset(rect.left + 3, y), 1, paint);
      canvas.drawCircle(Offset(rect.right - 3, y), 1, paint);
    }
  }

  void _tape(Canvas canvas, Offset center, double scale, double rotation) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.scale(scale);
    final path = Path()
      ..moveTo(-20, -6)
      ..lineTo(20, -6)
      ..lineTo(17, -3)
      ..lineTo(20, 0)
      ..lineTo(17, 3)
      ..lineTo(20, 6)
      ..lineTo(-20, 6)
      ..lineTo(-17, 3)
      ..lineTo(-20, 0)
      ..lineTo(-17, -3)
      ..close();
    canvas.drawPath(path,
        Paint()..color = Color.lerp(fill, accent, .18)!.withValues(alpha: .9));
    canvas.save();
    canvas.clipPath(path);
    for (double x = -26; x < 25; x += 7) {
      canvas.drawLine(
          Offset(x, -7),
          Offset(x + 10, 7),
          Paint()
            ..color = Colors.white.withValues(alpha: .5)
            ..strokeWidth = 2);
    }
    canvas.restore();
    canvas.restore();
  }

  void _heart(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy + r)
          ..cubicTo(
              c.dx - r * 2, c.dy, c.dx - r, c.dy - r * 1.5, c.dx, c.dy - r * .4)
          ..cubicTo(
              c.dx + r, c.dy - r * 1.5, c.dx + r * 2, c.dy, c.dx, c.dy + r),
        Paint()..color = color);
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color, Color border) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * .2, c.dy - r * .2, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + r * .2, c.dy + r * .2, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r * .2, c.dy + r * .2, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - r * .2, c.dy - r * .2, c.dx, c.dy - r);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7);
  }

  @override
  bool shouldRepaint(BubbleArtworkPainter oldDelegate) =>
      id != oldDelegate.id ||
      isUser != oldDelegate.isUser ||
      fill != oldDelegate.fill ||
      accent != oldDelegate.accent ||
      compact != oldDelegate.compact ||
      radius != oldDelegate.radius;
}
