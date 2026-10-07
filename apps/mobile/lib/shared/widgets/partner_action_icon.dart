import 'package:flutter/material.dart';

enum PartnerActionSymbol { edit, chat }

class PartnerActionIcon extends StatelessWidget {
  const PartnerActionIcon({required this.symbol, super.key});

  final PartnerActionSymbol symbol;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    final inheritedColor =
        theme.color ?? Theme.of(context).colorScheme.onSurface;
    final color = inheritedColor.withValues(
        alpha: inheritedColor.a * (theme.opacity ?? 1));
    return ExcludeSemantics(
        child: CustomPaint(
            size: Size.square(size),
            painter: _PartnerActionPainter(symbol, color)));
  }
}

class _PartnerActionPainter extends CustomPainter {
  const _PartnerActionPainter(this.symbol, this.color);
  final PartnerActionSymbol symbol;
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
    final path = Path();
    switch (symbol) {
      case PartnerActionSymbol.edit:
        path
          ..moveTo(5, 19)
          ..lineTo(9, 18.2)
          ..lineTo(19.2, 8)
          ..arcToPoint(const Offset(16, 4.8),
              radius: const Radius.circular(2.3), clockwise: false)
          ..lineTo(5.8, 15)
          ..close()
          ..moveTo(14.8, 6)
          ..lineTo(18, 9.2);
      case PartnerActionSymbol.chat:
        path
          ..moveTo(20, 11)
          ..arcToPoint(const Offset(12, 19), radius: const Radius.circular(8))
          ..lineTo(7, 19)
          ..lineTo(3, 22)
          ..lineTo(4, 16)
          ..arcToPoint(const Offset(20, 11),
              radius: const Radius.circular(8), largeArc: true)
          ..close();
        for (final position in [8.0, 12.0, 16.0]) {
          canvas.drawLine(
              Offset(position, 11), Offset(position + .1, 11), stroke);
        }
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _PartnerActionPainter oldDelegate) =>
      oldDelegate.symbol != symbol || oldDelegate.color != color;
}
