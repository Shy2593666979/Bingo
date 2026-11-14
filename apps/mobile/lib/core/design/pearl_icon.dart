import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The 24px, 1.6px rounded outline family used by the pearl concept.
enum PearlSymbol {
  plus,
  home,
  chat,
  compass,
  person,
  personAdd,
  group,
  bell,
  edit,
  mic,
  share,
  palette,
  settings,
  chatAdd
}

class PearlIcon extends StatelessWidget {
  const PearlIcon(this.symbol,
      {this.size = 24,
      this.color = const Color(0xFF24212B),
      this.selected = false,
      super.key});
  final PearlSymbol symbol;
  final double size;
  final Color color;
  final bool selected;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _Painter(symbol, color, selected)));
}

class _Painter extends CustomPainter {
  const _Painter(this.symbol, this.color, this.selected);
  final PearlSymbol symbol;
  final Color color;
  final bool selected;
  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    void path(Path q, {bool solid = false}) {
      if (solid) c.drawPath(q, fill);
      c.drawPath(q, p);
    }

    void line(double x, double y, double a, double b) =>
        c.drawLine(Offset(x, y), Offset(a, b), p);
    void head(double x, double y, double r) => c.drawCircle(Offset(x, y), r, p);
    switch (symbol) {
      case PearlSymbol.plus:
        final plusPaint = Paint()
          ..color = color
          ..strokeWidth = 2.1
          ..strokeCap = StrokeCap.round;
        c.drawLine(const Offset(3, 12), const Offset(21, 12), plusPaint);
        c.drawLine(const Offset(12, 3), const Offset(12, 21), plusPaint);
      case PearlSymbol.home:
        final q = Path()
          ..moveTo(3.3, 10.5)
          ..quadraticBezierTo(3.3, 9.4, 4.3, 8.7)
          ..lineTo(10.3, 4.3)
          ..quadraticBezierTo(12, 3, 13.7, 4.3)
          ..lineTo(19.7, 8.7)
          ..quadraticBezierTo(20.7, 9.4, 20.7, 10.5)
          ..lineTo(20.7, 19.5)
          ..quadraticBezierTo(20.7, 21, 19.2, 21)
          ..lineTo(15.2, 21)
          ..lineTo(15.2, 15.2)
          ..quadraticBezierTo(15.2, 14, 14, 14)
          ..lineTo(10, 14)
          ..quadraticBezierTo(8.8, 14, 8.8, 15.2)
          ..lineTo(8.8, 21)
          ..lineTo(4.8, 21)
          ..quadraticBezierTo(3.3, 21, 3.3, 19.5)
          ..close();
        path(q, solid: selected);
      case PearlSymbol.chat:
      case PearlSymbol.chatAdd:
        final q = Path()
          ..moveTo(6, 4.5)
          ..lineTo(18, 4.5)
          ..quadraticBezierTo(22, 4.5, 22, 8)
          ..lineTo(22, 15.5)
          ..quadraticBezierTo(22, 19, 18, 19)
          ..lineTo(10, 19)
          ..lineTo(5.8, 21.5)
          ..lineTo(6, 18.8)
          ..quadraticBezierTo(2, 18, 2, 15.5)
          ..lineTo(2, 8)
          ..quadraticBezierTo(2, 4.5, 6, 4.5)
          ..close();
        path(q, solid: selected);
        final dot = Paint()..color = selected ? Colors.white : color;
        if (symbol == PearlSymbol.chatAdd) {
          line(9, 11, 15, 11);
          line(12, 8, 12, 14);
        } else {
          for (final x in [8.0, 12.0, 16.0]) {
            c.drawCircle(Offset(x, 11.5), .9, dot);
          }
        }
      case PearlSymbol.compass:
        head(12, 12, 9.5);
        final q = Path()
          ..moveTo(16.3, 7.7)
          ..quadraticBezierTo(15.2, 12, 13.5, 13.5)
          ..quadraticBezierTo(12, 15.2, 7.7, 16.3)
          ..quadraticBezierTo(8.8, 12, 10.5, 10.5)
          ..quadraticBezierTo(12, 8.8, 16.3, 7.7)
          ..close();
        if (selected) {
          c.drawCircle(const Offset(12, 12), 9.5, fill);
        }
        final needle = selected ? (Paint()..color = Colors.white) : fill;
        c.drawPath(q, needle);
        c.drawLine(
            const Offset(10.8, 13.2),
            const Offset(13.3, 10.7),
            Paint()
              ..color = (selected ? color : Colors.white)
              ..strokeWidth = 1.2
              ..strokeCap = StrokeCap.round);
      case PearlSymbol.person:
        final face = Paint()
          ..color = color
          ..style = selected ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.65;
        c.drawCircle(const Offset(12, 6.3), 3.5, face);
        path(
            Path()
              ..moveTo(4, 20.5)
              ..cubicTo(1.5, 20.5, 3, 16.7, 5.5, 15.2)
              ..cubicTo(9, 13.1, 15, 13.1, 18.5, 15.2)
              ..cubicTo(21, 16.7, 22.5, 20.5, 20, 20.5)
              ..close(),
            solid: selected);
      case PearlSymbol.personAdd:
        head(9, 7, 3.4);
        path(Path()
          ..moveTo(2, 21)
          ..lineTo(2, 18)
          ..cubicTo(2, 12, 16, 12, 16, 18)
          ..lineTo(16, 21)
          ..close());
        line(20, 7, 20, 13);
        line(17, 10, 23, 10);
      case PearlSymbol.group:
        head(12, 7, 3);
        head(4.5, 9, 2);
        head(19.5, 9, 2);
        path(Path()
          ..moveTo(6, 21)
          ..lineTo(6, 17)
          ..cubicTo(6, 11, 18, 11, 18, 17)
          ..lineTo(18, 21)
          ..close());
        path(Path()
          ..moveTo(3, 20)
          ..lineTo(1, 20)
          ..lineTo(1, 16)
          ..quadraticBezierTo(1, 13, 4, 13));
        path(Path()
          ..moveTo(21, 20)
          ..lineTo(23, 20)
          ..lineTo(23, 16)
          ..quadraticBezierTo(23, 13, 20, 13));
      case PearlSymbol.bell:
        path(Path()
          ..moveTo(5, 17)
          ..lineTo(6, 14)
          ..lineTo(6, 10)
          ..cubicTo(6, 2, 18, 2, 18, 10)
          ..lineTo(18, 14)
          ..lineTo(19, 17)
          ..close());
        c.drawArc(const Rect.fromLTWH(10, 18, 4, 3), 0, math.pi, false, p);
      case PearlSymbol.edit:
        path(Path()
          ..moveTo(10, 4)
          ..lineTo(5, 4)
          ..quadraticBezierTo(3, 4, 3, 6)
          ..lineTo(3, 19)
          ..quadraticBezierTo(3, 21, 5, 21)
          ..lineTo(18, 21)
          ..quadraticBezierTo(20, 21, 20, 19)
          ..lineTo(20, 14));
        path(Path()
          ..moveTo(10, 15)
          ..lineTo(11, 11)
          ..lineTo(19, 3)
          ..quadraticBezierTo(21, 1, 23, 4)
          ..lineTo(14, 13)
          ..close());
      case PearlSymbol.mic:
        c.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(9, 2, 6, 13), const Radius.circular(3)),
            p);
        path(Path()
          ..moveTo(5, 10)
          ..lineTo(5, 13)
          ..cubicTo(5, 22, 19, 22, 19, 13)
          ..lineTo(19, 10));
        line(12, 20, 12, 23);
      case PearlSymbol.share:
        head(18, 4, 3);
        head(5, 12, 3);
        head(18, 20, 3);
        line(7.5, 10.4, 15.4, 5.6);
        line(7.5, 13.6, 15.4, 18.4);
      case PearlSymbol.palette:
        path(Path()
          ..moveTo(21, 12)
          ..cubicTo(21, 1, 3, 0, 2, 11)
          ..cubicTo(1, 22, 17, 25, 16, 18)
          ..cubicTo(15, 14, 21, 17, 21, 12)
          ..close());
        for (final o in [
          const Offset(7, 8),
          const Offset(12, 5),
          const Offset(17, 8),
          const Offset(6, 13)
        ]) {
          c.drawCircle(o, 1.1, fill);
        }
      case PearlSymbol.settings:
        final q = Path();
        for (var i = 0; i < 24; i++) {
          final a = i * math.pi / 12;
          final r = (i % 3 == 0) ? 10.5 : 8.5;
          final x = 12 + r * math.cos(a), y = 12 + r * math.sin(a);
          if (i == 0) {
            q.moveTo(x, y);
          } else {
            q.lineTo(x, y);
          }
        }
        q.close();
        path(q);
        head(12, 12, 3.5);
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) =>
      old.symbol != symbol || old.color != color || old.selected != selected;
}
