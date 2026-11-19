import 'package:flutter/material.dart';

enum ProfileMenuSymbol { me, group, waveform, share, star, shirt, settings }

/// Menu artwork drawn in logical coordinates; no screenshot or bitmap assets.
class ProfileMenuIcon extends StatelessWidget {
  const ProfileMenuIcon(this.symbol, {super.key});
  final ProfileMenuSymbol symbol;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 32,
        child: CustomPaint(painter: _ProfileMenuPainter(symbol)),
      );
}

class _ProfileMenuPainter extends CustomPainter {
  const _ProfileMenuPainter(this.symbol);
  final ProfileMenuSymbol symbol;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final paint = Paint()
      ..color = const Color(0xFF2C333D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (symbol) {
      case ProfileMenuSymbol.me:
        final path = Path();
        path.addOval(
            Rect.fromCircle(center: const Offset(16, 10), radius: 5.5));
        path.moveTo(5.5, 28);
        path.cubicTo(5.5, 22, 9.7, 19, 16, 19);
        path.cubicTo(22.3, 19, 26.5, 22, 26.5, 28);
        canvas.drawPath(path, paint);
        break;
      case ProfileMenuSymbol.group:
        final path = Path();
        path.addOval(Rect.fromCircle(center: const Offset(12, 9), radius: 4.6));
        path.moveTo(3.5, 27);
        path.lineTo(3.5, 24.5);
        path.cubicTo(3.5, 19.8, 7, 17.7, 12, 17.7);
        path.cubicTo(17, 17.7, 20.5, 19.8, 20.5, 24.5);
        path.lineTo(20.5, 27);
        path.moveTo(21, 5.5);
        path.cubicTo(27.4, 5.5, 27.4, 14, 21, 14);
        path.moveTo(24, 18);
        path.cubicTo(28.2, 18.6, 29, 21, 29, 24.5);
        path.lineTo(29, 27);
        canvas.drawPath(path, paint);
        break;
      case ProfileMenuSymbol.waveform:
        final path = Path();
        path.moveTo(5, 14);
        path.lineTo(5, 18);
        path.moveTo(10.5, 9);
        path.lineTo(10.5, 23);
        path.moveTo(16, 4.5);
        path.lineTo(16, 27.5);
        path.moveTo(21.5, 8);
        path.lineTo(21.5, 24);
        path.moveTo(27, 14);
        path.lineTo(27, 18);
        canvas.drawPath(path, paint);
        break;
      case ProfileMenuSymbol.share:
        final path = Path();
        path.moveTo(10.5, 14);
        path.lineTo(20.5, 8);
        path.moveTo(10.5, 18);
        path.lineTo(20.5, 24);
        path.addOval(Rect.fromCircle(center: const Offset(7, 16), radius: 4));
        path.addOval(Rect.fromCircle(center: const Offset(24, 6), radius: 4));
        path.addOval(Rect.fromCircle(center: const Offset(24, 26), radius: 4));
        canvas.drawPath(path, paint);
        break;
      case ProfileMenuSymbol.shirt:
        final path = Path();
        path.moveTo(10, 5.5);
        path.lineTo(4, 8.5);
        path.quadraticBezierTo(2.5, 9.2, 3.2, 10.8);
        path.lineTo(5, 15);
        path.quadraticBezierTo(5.5, 16, 6.6, 15.6);
        path.lineTo(9, 14.5);
        path.lineTo(9, 26);
        path.quadraticBezierTo(9, 27.5, 10.5, 27.5);
        path.lineTo(21.5, 27.5);
        path.quadraticBezierTo(23, 27.5, 23, 26);
        path.lineTo(23, 14.5);
        path.lineTo(25.4, 15.6);
        path.quadraticBezierTo(26.5, 16, 27, 15);
        path.lineTo(28.8, 10.8);
        path.quadraticBezierTo(29.5, 9.2, 28, 8.5);
        path.lineTo(22, 5.5);
        path.quadraticBezierTo(20.5, 5, 20, 6.5);
        path.cubicTo(18.7, 10.3, 13.3, 10.3, 12, 6.5);
        path.quadraticBezierTo(11.5, 5, 10, 5.5);
        canvas.drawPath(path, paint);
        break;
      case ProfileMenuSymbol.star:
        final path = Path();
        path.moveTo(15.4, 4.765);
        path.quadraticBezierTo(16, 3.5, 16.6, 4.765);
        path.lineTo(18.986, 9.8);
        path.quadraticBezierTo(19.585, 11.065, 20.974, 11.244);
        path.lineTo(26.5, 11.958);
        path.quadraticBezierTo(27.888, 12.137, 26.87, 13.098);
        path.lineTo(22.819, 16.924);
        path.quadraticBezierTo(21.801, 17.885, 22.06, 19.261);
        path.lineTo(23.089, 24.737);
        path.quadraticBezierTo(23.347, 26.113, 22.119, 25.442);
        path.lineTo(17.229, 22.771);
        path.quadraticBezierTo(16, 22.1, 14.771, 22.771);
        path.lineTo(9.881, 25.442);
        path.quadraticBezierTo(8.653, 26.113, 8.911, 24.737);
        path.lineTo(9.94, 19.261);
        path.quadraticBezierTo(10.199, 17.885, 9.181, 16.924);
        path.lineTo(5.13, 13.098);
        path.quadraticBezierTo(4.112, 12.137, 5.5, 11.958);
        path.lineTo(11.026, 11.244);
        path.quadraticBezierTo(12.415, 11.065, 13.014, 9.8);
        path.close();
        canvas.drawPath(path, paint);
        break;
      case ProfileMenuSymbol.settings:
        final path = Path();
        path.moveTo(25.253, 12.209);
        path.quadraticBezierTo(25.287, 12.291, 25.895, 12.52);
        path.lineTo(27.395, 13.086);
        path.quadraticBezierTo(28.004, 13.316, 28.004, 13.966);
        path.lineTo(28.004, 18.034);
        path.quadraticBezierTo(28.004, 18.684, 27.395, 18.914);
        path.lineTo(25.895, 19.48);
        path.quadraticBezierTo(25.287, 19.709, 25.253, 19.791);
        path.lineTo(25.223, 19.862);
        path.quadraticBezierTo(25.189, 19.944, 25.457, 20.536);
        path.lineTo(26.118, 21.997);
        path.quadraticBezierTo(26.386, 22.59, 25.926, 23.049);
        path.lineTo(23.049, 25.926);
        path.quadraticBezierTo(22.59, 26.386, 21.997, 26.118);
        path.lineTo(20.536, 25.457);
        path.quadraticBezierTo(19.944, 25.189, 19.862, 25.223);
        path.lineTo(19.791, 25.253);
        path.quadraticBezierTo(19.709, 25.287, 19.48, 25.895);
        path.lineTo(18.914, 27.395);
        path.quadraticBezierTo(18.684, 28.004, 18.034, 28.004);
        path.lineTo(13.966, 28.004);
        path.quadraticBezierTo(13.316, 28.004, 13.086, 27.395);
        path.lineTo(12.52, 25.895);
        path.quadraticBezierTo(12.291, 25.287, 12.209, 25.253);
        path.lineTo(12.138, 25.223);
        path.quadraticBezierTo(12.056, 25.189, 11.464, 25.457);
        path.lineTo(10.003, 26.118);
        path.quadraticBezierTo(9.41, 26.386, 8.951, 25.926);
        path.lineTo(6.074, 23.049);
        path.quadraticBezierTo(5.614, 22.59, 5.882, 21.997);
        path.lineTo(6.543, 20.536);
        path.quadraticBezierTo(6.811, 19.944, 6.777, 19.862);
        path.lineTo(6.747, 19.791);
        path.quadraticBezierTo(6.713, 19.709, 6.105, 19.48);
        path.lineTo(4.605, 18.914);
        path.quadraticBezierTo(3.996, 18.684, 3.996, 18.034);
        path.lineTo(3.996, 13.966);
        path.quadraticBezierTo(3.996, 13.316, 4.605, 13.086);
        path.lineTo(6.105, 12.52);
        path.quadraticBezierTo(6.713, 12.291, 6.747, 12.209);
        path.lineTo(6.777, 12.138);
        path.quadraticBezierTo(6.811, 12.056, 6.543, 11.464);
        path.lineTo(5.882, 10.003);
        path.quadraticBezierTo(5.614, 9.41, 6.074, 8.951);
        path.lineTo(8.951, 6.074);
        path.quadraticBezierTo(9.41, 5.614, 10.003, 5.882);
        path.lineTo(11.464, 6.543);
        path.quadraticBezierTo(12.056, 6.811, 12.138, 6.777);
        path.lineTo(12.209, 6.747);
        path.quadraticBezierTo(12.291, 6.713, 12.52, 6.105);
        path.lineTo(13.086, 4.605);
        path.quadraticBezierTo(13.316, 3.996, 13.966, 3.996);
        path.lineTo(18.034, 3.996);
        path.quadraticBezierTo(18.684, 3.996, 18.914, 4.605);
        path.lineTo(19.48, 6.105);
        path.quadraticBezierTo(19.709, 6.713, 19.791, 6.747);
        path.lineTo(19.862, 6.777);
        path.quadraticBezierTo(19.944, 6.811, 20.536, 6.543);
        path.lineTo(21.997, 5.882);
        path.quadraticBezierTo(22.59, 5.614, 23.049, 6.074);
        path.lineTo(25.926, 8.951);
        path.quadraticBezierTo(26.386, 9.41, 26.118, 10.003);
        path.lineTo(25.457, 11.464);
        path.quadraticBezierTo(25.189, 12.056, 25.223, 12.138);
        path.close();
        path.addOval(Rect.fromCircle(center: const Offset(16, 16), radius: 4));
        canvas.drawPath(path, paint);
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProfileMenuPainter oldDelegate) =>
      oldDelegate.symbol != symbol;
}
