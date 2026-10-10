import 'package:flutter/material.dart';

class AccountDeletionIcon extends StatelessWidget {
  const AccountDeletionIcon(
      {this.size = 24, this.color = const Color(0xFFBE7870), super.key});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size, child: CustomPaint(painter: _PowerPainter(color)));
}

class _PowerPainter extends CustomPainter {
  const _PowerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(8.20514, 4.84312)
      ..cubicTo(8.70586, 4.61008, 9.30068, 4.82707, 9.53372, 5.32778)
      ..cubicTo(9.76676, 5.82849, 9.54977, 6.42331, 9.04906, 6.65635)
      ..cubicTo(6.59946, 7.79644, 5, 10.2547, 5, 13.003)
      ..cubicTo(5, 16.8671, 8.13391, 19.9997, 12, 19.9997)
      ..cubicTo(15.8661, 19.9997, 19, 16.8671, 19, 13.003)
      ..cubicTo(19, 10.2604, 17.4072, 7.80631, 14.9653, 6.66304)
      ..cubicTo(14.4651, 6.42887, 14.2495, 5.83355, 14.4836, 5.33337)
      ..cubicTo(14.7178, 4.83319, 15.3131, 4.61756, 15.8133, 4.85173)
      ..cubicTo(18.9517, 6.32109, 21, 9.47689, 21, 13.003)
      ..cubicTo(21, 17.9719, 16.9705, 21.9997, 12, 21.9997)
      ..cubicTo(7.02953, 21.9997, 3, 17.9719, 3, 13.003)
      ..cubicTo(3, 9.46957, 5.05682, 6.30841, 8.20514, 4.84312)
      ..close()
      ..moveTo(12, 1.99902)
      ..cubicTo(12.5128, 1.99902, 12.9355, 2.38506, 12.9933, 2.8824)
      ..lineTo(13, 2.99902)
      ..lineTo(13, 10.0004)
      ..cubicTo(13, 10.5527, 12.5523, 11.0004, 12, 11.0004)
      ..cubicTo(11.4872, 11.0004, 11.0645, 10.6144, 11.0067, 10.1171)
      ..lineTo(11, 10.0004)
      ..lineTo(11, 2.99902)
      ..cubicTo(11, 2.44674, 11.4477, 1.99902, 12, 1.99902)
      ..close();
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PowerPainter oldDelegate) => oldDelegate.color != color;
}
