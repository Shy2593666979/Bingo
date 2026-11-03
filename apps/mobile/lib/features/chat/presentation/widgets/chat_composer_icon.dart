import 'package:flutter/material.dart';

enum ChatComposerSymbol { voice, keyboard, add, addOutlined, send }

/// Small composer controls share the same rounded, optical stroke weight.
class ChatComposerIcon extends StatelessWidget {
  const ChatComposerIcon(this.symbol,
      {required this.color, this.size = 27, super.key});

  final ChatComposerSymbol symbol;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ComposerIconPainter(symbol, color)));
}

class _ComposerIconPainter extends CustomPainter {
  const _ComposerIconPainter(this.symbol, this.color);
  final ChatComposerSymbol symbol;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 28, size.height / 28);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (symbol) {
      case ChatComposerSymbol.voice:
        canvas.drawCircle(const Offset(14, 14), 10.8, stroke);
        canvas.drawLine(const Offset(8.6, 12), const Offset(8.6, 16), stroke);
        canvas.drawLine(const Offset(14, 8.3), const Offset(14, 19.7), stroke);
        canvas.drawLine(
            const Offset(19.4, 10.4), const Offset(19.4, 17.6), stroke);
      case ChatComposerSymbol.keyboard:
        canvas.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(2.7, 5.5, 22.6, 17),
                const Radius.circular(4)),
            stroke);
        final key = Paint()
          ..color = color
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        for (final y in [10.0, 14.0]) {
          for (final x in [7.5, 12.0, 16.5, 21.0]) {
            canvas.drawLine(Offset(x, y), Offset(x + .1, y), key);
          }
        }
        canvas.drawLine(const Offset(9, 18.2), const Offset(19, 18.2), stroke);
      case ChatComposerSymbol.add:
        stroke.strokeWidth = 2.1;
        canvas.drawLine(const Offset(14, 5.5), const Offset(14, 22.5), stroke);
        canvas.drawLine(const Offset(5.5, 14), const Offset(22.5, 14), stroke);
      case ChatComposerSymbol.addOutlined:
        canvas.drawCircle(const Offset(14, 14), 10.8, stroke);
        canvas.drawLine(const Offset(14, 8), const Offset(14, 20), stroke);
        canvas.drawLine(const Offset(8, 14), const Offset(20, 14), stroke);
      case ChatComposerSymbol.send:
        stroke.strokeWidth = 2;
        canvas.drawPath(
            Path()
              ..moveTo(5, 14)
              ..lineTo(23, 14)
              ..moveTo(15, 6)
              ..lineTo(23, 14)
              ..lineTo(15, 22),
            stroke);
    }
  }

  @override
  bool shouldRepaint(_ComposerIconPainter oldDelegate) =>
      symbol != oldDelegate.symbol || color != oldDelegate.color;
}
