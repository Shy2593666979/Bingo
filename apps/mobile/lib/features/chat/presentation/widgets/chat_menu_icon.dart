import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

enum ChatMenuSymbol { photo, camera, call, point, focus, promise, sleep, diary }

class ChatMenuIcon extends StatelessWidget {
  const ChatMenuIcon({super.key, required this.symbol, this.size = 22});

  final ChatMenuSymbol symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChatMenuIconPainter(symbol),
    );
  }
}

class _ChatMenuIconPainter extends CustomPainter {
  const _ChatMenuIconPainter(this.symbol);

  final ChatMenuSymbol symbol;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = BingoPalette.chatMenuInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (symbol) {
      case ChatMenuSymbol.photo:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(3, 4, 18, 16), const Radius.circular(3)),
          stroke,
        );
        path
          ..moveTo(4, 17)
          ..lineTo(9, 12)
          ..lineTo(13, 16)
          ..lineTo(16, 13)
          ..lineTo(20, 17);
        canvas.drawCircle(const Offset(15, 9), 1, stroke);
      case ChatMenuSymbol.camera:
        path
          ..moveTo(3, 8)
          ..lineTo(7, 8)
          ..lineTo(9, 4)
          ..lineTo(15, 4)
          ..lineTo(17, 8)
          ..lineTo(21, 8)
          ..lineTo(21, 20)
          ..lineTo(3, 20)
          ..close();
        canvas.drawCircle(const Offset(12, 13), 4, stroke);
      case ChatMenuSymbol.call:
        path
          ..moveTo(6, 3)
          ..lineTo(10, 8)
          ..lineTo(8, 11)
          ..cubicTo(9, 14, 11, 16, 14, 17)
          ..lineTo(17, 15)
          ..lineTo(21, 18)
          ..cubicTo(21, 21, 19, 22, 17, 21)
          ..cubicTo(9, 19, 4, 14, 3, 7)
          ..cubicTo(3, 5, 4, 3, 6, 3)
          ..close();
      case ChatMenuSymbol.point:
        path
          ..moveTo(19, 10)
          ..cubicTo(19, 15, 12, 21, 12, 21)
          ..cubicTo(12, 21, 5, 15, 5, 10)
          ..arcToPoint(const Offset(19, 10),
              radius: const Radius.circular(7), largeArc: true)
          ..close();
        canvas.drawCircle(const Offset(12, 10), 2, stroke);
      case ChatMenuSymbol.focus:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        path
          ..moveTo(12, 7)
          ..lineTo(12, 12)
          ..lineTo(15, 14);
      case ChatMenuSymbol.promise:
        path
          ..moveTo(12, 20)
          ..lineTo(3.6, 12)
          ..arcToPoint(const Offset(12, 5.4),
              radius: const Radius.circular(5.3))
          ..arcToPoint(const Offset(20.4, 12),
              radius: const Radius.circular(5.3))
          ..close();
      case ChatMenuSymbol.sleep:
        path
          ..moveTo(20, 15)
          ..arcToPoint(const Offset(9, 3), radius: const Radius.circular(9))
          ..arcToPoint(const Offset(20, 15),
              radius: const Radius.circular(9),
              largeArc: true,
              clockwise: false)
          ..close();
      case ChatMenuSymbol.diary:
        path
          ..moveTo(6, 3)
          ..lineTo(17, 3)
          ..arcToPoint(const Offset(19, 5), radius: const Radius.circular(2))
          ..lineTo(19, 21)
          ..lineTo(6, 21)
          ..arcToPoint(const Offset(3, 18), radius: const Radius.circular(3))
          ..lineTo(3, 6)
          ..arcToPoint(const Offset(6, 3), radius: const Radius.circular(3))
          ..close()
          ..moveTo(6, 3)
          ..lineTo(6, 21)
          ..moveTo(10, 8)
          ..lineTo(15, 8)
          ..moveTo(10, 12)
          ..lineTo(15, 12)
          ..moveTo(10, 16)
          ..lineTo(13, 16);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ChatMenuIconPainter oldDelegate) =>
      symbol != oldDelegate.symbol;
}
