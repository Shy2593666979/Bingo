import 'package:flutter/material.dart';

enum HomeArtwork {
  wave,
  conversation,
  home,
  chatTab,
  create,
  plus,
  compass,
  profile,
  back,
  next,
}

/// Original vector artwork for the selected home design.
class HomeArtworkIcon extends StatelessWidget {
  const HomeArtworkIcon(this.artwork,
      {required this.color, this.size = 24, super.key});

  final HomeArtwork artwork;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _HomeArtworkPainter(artwork, color)));
}

class _HomeArtworkPainter extends CustomPainter {
  const _HomeArtworkPainter(this.artwork, this.color);

  final HomeArtwork artwork;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final ink = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (artwork) {
      case HomeArtwork.wave:
        canvas.save();
        canvas.scale(.6);
        line.strokeWidth = 1.8;
        canvas.drawPath(
            Path()
              ..moveTo(5.8, 29.4)
              ..relativeCubicTo(-1, -2.2, .2, -5.1, .8, -7.9)
              ..relativeLineTo(1.1, -4.7)
              ..relativeCubicTo(.5, -2.2, 3.5, -2, 3.5, .2)
              ..relativeLineTo(-.4, 5.6)
              ..relativeLineTo(6.5, -8.9)
              ..relativeCubicTo(1.4, -2, 4.1, -.2, 2.8, 1.8)
              ..relativeLineTo(-5.6, 8)
              ..relativeLineTo(7.5, -9)
              ..relativeCubicTo(1.5, -1.8, 4.1, .2, 2.7, 2)
              ..relativeLineTo(-7, 9.2)
              ..relativeLineTo(7.3, -7)
              ..relativeCubicTo(1.7, -1.6, 4, .6, 2.4, 2.3)
              ..relativeLineTo(-7, 7.5)
              ..relativeLineTo(6.3, -4.7)
              ..relativeCubicTo(1.8, -1.4, 3.8, .9, 2.1, 2.6)
              ..relativeLineTo(-7.7, 7.2)
              ..relativeCubicTo(-2.8, 2.6, -6.3, 3.6, -9.6, 3.1),
            line);
        canvas.drawPath(
            Path()
              ..relativeMoveTo(18.7, 6.3)
              ..relativeLineTo(1.8, 4.1)
              ..relativeMoveTo(9, -6.9)
              ..relativeLineTo(-1.6, 4.7)
              ..relativeMoveTo(8.8, 1)
              ..relativeLineTo(-3.8, 2.8),
            line);
        canvas.restore();
        break;
      case HomeArtwork.conversation:
        canvas.drawPath(
          Path()
            ..moveTo(5, 18.1)
            ..cubicTo(3.1, 16.5, 2, 14.3, 2, 11.6)
            ..cubicTo(2, 6.4, 6.1, 2.5, 12.2, 2.5)
            ..cubicTo(18.1, 2.5, 22, 6.3, 22, 11.5)
            ..cubicTo(22, 16.7, 18, 20.4, 12.1, 20.4)
            ..cubicTo(10.7, 20.4, 9.3, 20.2, 8, 19.7)
            ..lineTo(3.5, 22)
            ..lineTo(5, 18.1)
            ..close(),
          line..strokeWidth = 1.7,
        );
        for (final x in [8.0, 12.0, 16.0]) {
          canvas.drawCircle(Offset(x, 11.5), .9, ink);
        }
        break;
      case HomeArtwork.home:
        canvas.drawPath(
          Path()
            ..moveTo(11, 1.8)
            ..quadraticBezierTo(12, .9, 13, 1.8)
            ..lineTo(22, 9)
            ..quadraticBezierTo(23, 9.8, 23, 11.1)
            ..lineTo(23, 21)
            ..quadraticBezierTo(23, 22.7, 21.2, 22.7)
            ..lineTo(16.5, 22.7)
            ..quadraticBezierTo(15.3, 22.7, 15.3, 21.5)
            ..lineTo(15.3, 18)
            ..quadraticBezierTo(15.3, 15.9, 13.4, 15.9)
            ..lineTo(10.6, 15.9)
            ..quadraticBezierTo(8.7, 15.9, 8.7, 18)
            ..lineTo(8.7, 21.5)
            ..quadraticBezierTo(8.7, 22.7, 7.5, 22.7)
            ..lineTo(2.8, 22.7)
            ..quadraticBezierTo(1, 22.7, 1, 21)
            ..lineTo(1, 11.1)
            ..quadraticBezierTo(1, 9.8, 2, 9)
            ..close(),
          ink,
        );
        break;
      case HomeArtwork.chatTab:
        canvas.drawPath(
          Path()
            ..moveTo(3, 17)
            ..quadraticBezierTo(1.6, 16.3, 1.6, 14)
            ..lineTo(1.6, 5.5)
            ..quadraticBezierTo(1.6, 2.8, 4.3, 2.8)
            ..lineTo(19.7, 2.8)
            ..quadraticBezierTo(22.4, 2.8, 22.4, 5.5)
            ..lineTo(22.4, 14)
            ..quadraticBezierTo(22.4, 17, 19.7, 17)
            ..lineTo(10.2, 17)
            ..lineTo(4.2, 21.2)
            ..lineTo(4.2, 17)
            ..close(),
          line,
        );
        for (final x in [7.8, 12.0, 16.2]) {
          canvas.drawCircle(Offset(x, 10), .95, ink);
        }
        break;
      case HomeArtwork.create:
        canvas.drawCircle(const Offset(12, 12), 11.8, ink);
        line
          ..color = Colors.white
          ..strokeWidth = 1.6;
        canvas.drawLine(const Offset(6.7, 12), const Offset(17.3, 12), line);
        canvas.drawLine(const Offset(12, 6.7), const Offset(12, 17.3), line);
        break;
      case HomeArtwork.plus:
        line.strokeWidth = 2.1;
        canvas.drawLine(const Offset(3.5, 12), const Offset(20.5, 12), line);
        canvas.drawLine(const Offset(12, 3.5), const Offset(12, 20.5), line);
        break;
      case HomeArtwork.compass:
        canvas.drawCircle(const Offset(12, 12), 10.8, line);
        canvas.drawPath(
          Path()
            ..moveTo(16.6, 7.5)
            ..lineTo(13.7, 13.7)
            ..lineTo(7.4, 16.6)
            ..lineTo(10.3, 10.3)
            ..close(),
          line..strokeWidth = 1.4,
        );
        break;
      case HomeArtwork.profile:
        canvas.drawCircle(const Offset(12, 6.1), 4.4, line);
        canvas.drawPath(
          Path()
            ..moveTo(2.1, 21.6)
            ..cubicTo(2.4, 17.1, 6.1, 14.6, 12, 14.6)
            ..cubicTo(17.9, 14.6, 21.6, 17.1, 21.9, 21.6)
            ..close(),
          line,
        );
        break;
      case HomeArtwork.back:
      case HomeArtwork.next:
        final direction = artwork == HomeArtwork.next ? 1 : -1;
        canvas.drawPath(
          Path()
            ..moveTo(12 - 2.5 * direction, 6.5)
            ..lineTo(12 + 2.5 * direction, 12)
            ..lineTo(12 - 2.5 * direction, 17.5),
          line..strokeWidth = 1.85,
        );
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HomeArtworkPainter oldDelegate) =>
      oldDelegate.artwork != artwork || oldDelegate.color != color;
}
