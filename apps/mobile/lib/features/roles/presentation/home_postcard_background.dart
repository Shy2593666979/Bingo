import 'dart:math' as math;

import 'package:flutter/material.dart';

class HomePostcardBackground extends CustomPainter {
  const HomePostcardBackground();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFBD6E4), Color(0xFFFFF5FA), Color(0xFFF9D7E6)],
        ).createShader(bounds),
    );

    canvas.save();
    canvas.scale(size.width / 360, size.height / 196);
    final whiteLine = Paint()
      ..color = const Color(0xEFFFFFFF)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(161, 72)
        ..cubicTo(186, 17, 230, 3, 266, 5)
        ..cubicTo(315, 6, 346, 28, 372, 70),
      whiteLine,
    );
    canvas.drawPath(
      Path()
        ..moveTo(244, 102)
        ..cubicTo(277, 48, 325, 46, 367, 61),
      whiteLine..color = const Color(0xBFFFFFFF),
    );
    final ribbon = Path()
      ..moveTo(0, 186)
      ..cubicTo(54, 180, 79, 197, 126, 189)
      ..cubicTo(185, 184, 222, 155, 281, 162)
      ..cubicTo(313, 167, 339, 165, 360, 149)
      ..lineTo(360, 196)
      ..lineTo(0, 196)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = const Color(0x28EF9ABD));

    final glint = Path()
      ..moveTo(335, 18)
      ..quadraticBezierTo(335, 25, 342, 25)
      ..quadraticBezierTo(335, 25, 335, 32)
      ..quadraticBezierTo(335, 25, 328, 25)
      ..quadraticBezierTo(335, 25, 335, 18)
      ..close();
    canvas.drawPath(glint, Paint()..color = Colors.white);

    final leaf = Paint()..color = const Color(0xFFB6B681);
    canvas.drawPath(
      Path()
        ..moveTo(326, 165)
        ..quadraticBezierTo(345, 144, 350, 133)
        ..quadraticBezierTo(339, 154, 328, 167)
        ..quadraticBezierTo(310, 185, 280, 190)
        ..quadraticBezierTo(307, 181, 326, 165),
      leaf,
    );
    canvas.drawPath(
      Path()
        ..moveTo(335, 154)
        ..quadraticBezierTo(325, 147, 331, 134)
        ..quadraticBezierTo(339, 144, 335, 154)
        ..quadraticBezierTo(342, 141, 355, 140)
        ..quadraticBezierTo(350, 150, 335, 154),
      leaf,
    );
    canvas.drawPath(
      Path()
        ..moveTo(301, 182)
        ..quadraticBezierTo(291, 178, 280, 189)
        ..quadraticBezierTo(292, 191, 301, 182),
      leaf,
    );
    canvas.translate(317, 174);
    final petal = Path()
      ..moveTo(0, 2)
      ..cubicTo(-7, 0, -9, -13, -4, -16)
      ..quadraticBezierTo(-1, -18, 1, -14)
      ..cubicTo(7, -20, 11, -10, 4, -1)
      ..close();
    for (var index = 0; index < 5; index++) {
      canvas.drawPath(
        petal,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF1F8), Color(0xFFF39ABF)],
          ).createShader(petal.getBounds()),
      );
      canvas.rotate(2 * math.pi / 5);
    }
    canvas.drawCircle(
        Offset.zero, 2.7, Paint()..color = const Color(0xFFF6C58C));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HomePostcardBackground oldDelegate) => false;
}
