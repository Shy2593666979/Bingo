import 'package:flutter/material.dart';

enum CompanionMenuSymbol {
  share,
  favorite,
  appearance,
  settings,
  chevron,
  refresh
}

/// The approved HTML menu outlines; appearance uses the app-wide palette glyph.
class CompanionMenuIcon extends StatelessWidget {
  const CompanionMenuIcon(this.symbol,
      {this.size = 25, this.color = const Color(0xFF284A33), super.key});
  final CompanionMenuSymbol symbol;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => symbol == CompanionMenuSymbol.appearance
      ? Icon(Icons.palette_outlined, size: size, color: color)
      : SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _MenuOutline(symbol, color)));
}

class _MenuOutline extends CustomPainter {
  const _MenuOutline(this.symbol, this.color);
  final CompanionMenuSymbol symbol;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = symbol == CompanionMenuSymbol.chevron ? 1.6 : 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (symbol) {
      case CompanionMenuSymbol.refresh:
        path
          ..moveTo(21, 8)
          ..arcToPoint(const Offset(21.1, 15),
              radius: const Radius.circular(9),
              largeArc: true,
              clockwise: false)
          ..moveTo(21, 2)
          ..lineTo(21, 8)
          ..lineTo(15, 8);
      case CompanionMenuSymbol.share:
        path
          ..moveTo(3, 16)
          ..lineTo(4, 10)
          ..lineTo(17, 1)
          ..lineTo(22, 6)
          ..lineTo(8, 20)
          ..lineTo(2, 22)
          ..close()
          ..moveTo(14, 4)
          ..lineTo(19, 9);
      case CompanionMenuSymbol.favorite:
        path
          ..moveTo(12, 1)
          ..lineTo(15.5, 8.2)
          ..lineTo(23, 9.3)
          ..lineTo(17.5, 14.6)
          ..lineTo(18.8, 22.1)
          ..lineTo(12, 18.6)
          ..lineTo(5.2, 22.1)
          ..lineTo(6.5, 14.6)
          ..lineTo(1, 9.3)
          ..lineTo(8.5, 8.2)
          ..close();
      case CompanionMenuSymbol.settings:
        path
          ..moveTo(9, 2)
          ..lineTo(15, 2)
          ..lineTo(16, 5)
          ..lineTo(19, 6)
          ..lineTo(22, 10)
          ..lineTo(20, 13)
          ..lineTo(21, 16)
          ..lineTo(17, 21)
          ..lineTo(13, 20)
          ..lineTo(10, 22)
          ..lineTo(5, 19)
          ..lineTo(5, 15)
          ..lineTo(2, 12)
          ..lineTo(4, 7)
          ..lineTo(8, 6)
          ..close()
          ..addOval(const Rect.fromLTWH(8, 8, 8, 8));
      case CompanionMenuSymbol.chevron:
        path
          ..moveTo(9, 4)
          ..lineTo(17, 12)
          ..lineTo(9, 20);
      case CompanionMenuSymbol.appearance:
        break;
    }
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_MenuOutline oldDelegate) =>
      oldDelegate.symbol != symbol || oldDelegate.color != color;
}
