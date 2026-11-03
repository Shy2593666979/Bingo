import 'dart:math' as math;
import 'package:flutter/material.dart';

enum BingoSymbol {
  home,
  chat,
  group,
  personAdd,
  partners,
  community,
  profile,
  voice,
  smile,
  add,
  send
}

/// A single rounded stroke family for the companion app's main controls.
class BingoIcon extends StatelessWidget {
  const BingoIcon(this.symbol,
      {this.size = 26,
      this.color = const Color(0xFF687B82),
      this.selected = false,
      super.key});
  final BingoSymbol symbol;
  final double size;
  final Color color;
  final bool selected;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BingoIconPainter(symbol, color, selected)));
}

class _BingoIconPainter extends CustomPainter {
  const _BingoIconPainter(this.symbol, this.color, this.selected);
  final BingoSymbol symbol;
  final Color color;
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 28, size.height / 28);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.85
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    void line(double x, double y, double x2, double y2) =>
        canvas.drawLine(Offset(x, y), Offset(x2, y2), stroke);
    switch (symbol) {
      case BingoSymbol.personAdd:
        canvas.drawCircle(const Offset(10.5, 8), 3.5, stroke);
        canvas.drawPath(
            Path()
              ..moveTo(3.5, 23)
              ..lineTo(3.5, 21)
              ..cubicTo(3.5, 13.8, 17.5, 13.8, 17.5, 21)
              ..lineTo(17.5, 23)
              ..close(),
            stroke);
        line(22, 5.5, 22, 11.5);
        line(19, 8.5, 25, 8.5);
      case BingoSymbol.group:
        // A clear foreground person and a smaller rear person keep the group
        // silhouette readable even beside a conversation title at 17 px.
        canvas.drawCircle(const Offset(10.5, 8), 3.5, stroke);
        canvas.drawPath(
            Path()
              ..moveTo(18.5, 6.5)
              ..cubicTo(23.5, 5.8, 24.2, 12.8, 19.3, 13.1),
            stroke);
        canvas.drawPath(
            Path()
              ..moveTo(3.5, 23)
              ..lineTo(3.5, 21)
              ..cubicTo(3.5, 13.8, 17.5, 13.8, 17.5, 21)
              ..lineTo(17.5, 23)
              ..close(),
            stroke);
        canvas.drawPath(
            Path()
              ..moveTo(20.5, 16.4)
              ..quadraticBezierTo(25, 17.2, 25, 21)
              ..lineTo(25, 23)
              ..lineTo(21.5, 23),
            stroke);
      case BingoSymbol.chat:
        final bubble = Path()
          ..moveTo(7.5, 4.5)
          ..lineTo(20.5, 4.5)
          ..quadraticBezierTo(25, 4.5, 25, 9)
          ..lineTo(25, 17)
          ..quadraticBezierTo(25, 21.5, 20.5, 21.5)
          ..lineTo(12, 21.5)
          ..lineTo(6.5, 25)
          ..lineTo(6.5, 21.3)
          ..quadraticBezierTo(3, 20.5, 3, 17)
          ..lineTo(3, 9)
          ..quadraticBezierTo(3, 4.5, 7.5, 4.5)
          ..close();
        if (selected) canvas.drawPath(bubble, fill);
        canvas.drawPath(bubble, stroke);
        for (final x in [9.0, 14.0, 19.0]) {
          canvas.drawCircle(
              Offset(x, 13),
              1.25,
              Paint()
                ..color = selected
                    ? (color.computeLuminance() > .7
                        ? const Color(0xFF159C80)
                        : Colors.white)
                    : color);
        }
      case BingoSymbol.home:
        final house = Path()
          ..moveTo(4, 12)
          ..lineTo(12, 4.6)
          ..quadraticBezierTo(14, 2.7, 16, 4.6)
          ..lineTo(24, 12)
          ..lineTo(24, 22)
          ..quadraticBezierTo(24, 24.5, 21.5, 24.5)
          ..lineTo(17, 24.5)
          ..lineTo(17, 17)
          ..lineTo(11, 17)
          ..lineTo(11, 24.5)
          ..lineTo(6.5, 24.5)
          ..quadraticBezierTo(4, 24.5, 4, 22)
          ..close();
        if (selected) canvas.drawPath(house, fill);
        canvas.drawPath(house, stroke);
      case BingoSymbol.partners:
        canvas.save();
        canvas.translate(14, 14);
        canvas.rotate(-.52);
        canvas.drawOval(const Rect.fromLTWH(-12.5, -4.8, 25, 9.6), stroke);
        canvas.restore();
        canvas.drawCircle(
            const Offset(14, 13),
            8.2,
            Paint()
              ..color = Colors.white);
        canvas.drawCircle(const Offset(14, 13), 8.2, stroke);
        canvas.drawCircle(const Offset(11.4, 12), 1, fill);
        canvas.drawCircle(const Offset(16.6, 12), 1, fill);
        canvas.drawArc(const Rect.fromLTWH(11.2, 12.6, 5.6, 4), .25,
            math.pi - .5, false, stroke);
        canvas.drawCircle(const Offset(24, 4), 1.4, fill);
      case BingoSymbol.community:
        canvas.drawCircle(const Offset(14, 7.5), 3.3, stroke);
        canvas.drawCircle(const Offset(5.7, 10.5), 2.5, stroke);
        canvas.drawCircle(const Offset(22.3, 10.5), 2.5, stroke);
        final people = Path()
          ..moveTo(8, 24)
          ..lineTo(8, 20)
          ..cubicTo(8, 12.4, 20, 12.4, 20, 20)
          ..lineTo(20, 24)
          ..close();
        if (selected) {
          canvas.drawPath(people, Paint()..color = color.withValues(alpha: .2));
        }
        canvas.drawPath(people, stroke);
        canvas.drawPath(
            Path()
              ..moveTo(5, 23)
              ..lineTo(2.5, 23)
              ..lineTo(2.5, 19)
              ..quadraticBezierTo(2.5, 15.5, 6, 15.5),
            stroke);
        canvas.drawPath(
            Path()
              ..moveTo(23, 23)
              ..lineTo(25.5, 23)
              ..lineTo(25.5, 19)
              ..quadraticBezierTo(25.5, 15.5, 22, 15.5),
            stroke);
      case BingoSymbol.profile:
        canvas.drawCircle(const Offset(6, 6), 3, stroke);
        canvas.drawCircle(const Offset(22, 6), 3, stroke);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(3.5, 5, 21, 20), const Radius.circular(10)),
            Paint()
              ..color = selected ? color.withValues(alpha: .14) : Colors.white);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(3.5, 5, 21, 20), const Radius.circular(10)),
            stroke);
        canvas.drawCircle(const Offset(10, 13), 1.15, fill);
        canvas.drawCircle(const Offset(18, 13), 1.15, fill);
        canvas.drawOval(const Rect.fromLTWH(12.6, 16, 2.8, 2.1), fill);
        canvas.drawArc(const Rect.fromLTWH(10.5, 15.5, 7, 5.5), .3,
            math.pi - .6, false, stroke);
      case BingoSymbol.voice:
        canvas.drawCircle(const Offset(14, 14), 11.5, stroke);
        line(8.3, 12.2, 8.3, 15.8);
        canvas.drawArc(
            const Rect.fromLTWH(4.2, 7.4, 14, 13.2), -.65, 1.3, false, stroke);
        canvas.drawArc(
            const Rect.fromLTWH(2.9, 4.6, 22, 18.8), -.65, 1.3, false, stroke);
      case BingoSymbol.smile:
        canvas.drawCircle(const Offset(14, 14), 10.7, stroke);
        canvas.drawCircle(const Offset(10, 11.5), 1.1, fill);
        canvas.drawCircle(const Offset(18, 11.5), 1.1, fill);
        canvas.drawArc(const Rect.fromLTWH(8.6, 11, 10.8, 9), .2, math.pi - .4,
            false, stroke);
      case BingoSymbol.add:
        canvas.drawCircle(const Offset(14, 14), 11.5, stroke);
        line(8.5, 14, 19.5, 14);
        line(14, 8.5, 14, 19.5);
      case BingoSymbol.send:
        line(14, 21, 14, 7);
        line(8, 13, 14, 7);
        line(14, 7, 20, 13);
    }
  }

  @override
  bool shouldRepaint(_BingoIconPainter old) =>
      old.symbol != symbol || old.color != color || old.selected != selected;
}
