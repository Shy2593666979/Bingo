import 'package:flutter/material.dart';

class CompanionRecordsIcon extends StatelessWidget {
  const CompanionRecordsIcon({this.color, this.size = 24, super.key});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
      child: CustomPaint(
          size: Size.square(size),
          painter: _RecordsPainter(color ??
              IconTheme.of(context).color ??
              Theme.of(context).colorScheme.onSurface)));
}

class _RecordsPainter extends CustomPainter {
  const _RecordsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTRB(5, 3, 21, 21), const Radius.circular(3)),
        stroke);
    for (final position in [7.0, 12.0, 17.0]) {
      canvas.drawLine(Offset(3, position), Offset(7, position), stroke);
    }
    final heart = Path()
      ..moveTo(13, 15.5)
      ..cubicTo(12, 14.6, 9, 12.6, 9, 10.7)
      ..cubicTo(9, 8.2, 12, 7.7, 13, 9.6)
      ..cubicTo(14, 7.7, 17, 8.2, 17, 10.7)
      ..cubicTo(17, 12.6, 14, 14.6, 13, 15.5)
      ..close();
    canvas.drawPath(heart, stroke);
    canvas.drawLine(const Offset(10, 18), const Offset(16, 18), stroke);
  }

  @override
  bool shouldRepaint(covariant _RecordsPainter oldDelegate) =>
      oldDelegate.color != color;
}
