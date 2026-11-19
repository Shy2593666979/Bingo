import 'package:bingo/core/design/home_artwork_icon.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class HomeGreeting extends StatelessWidget {
  const HomeGreeting({required this.nickname, super.key});

  final String? nickname;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? '上午好' : (hour < 18 ? '下午好' : '晚上好');
    final trimmed = nickname?.trim() ?? '';
    final name = trimmed.isEmpty ? '你' : trimmed;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 25, 6, 25),
        child: Wrap(
          spacing: 7,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('$greeting，',
                style: BingoTypography.sectionTitle.copyWith(fontSize: 24)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: CustomPaint(
                  painter: const _GreetingStroke(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(name,
                        style: BingoTypography.sectionTitle.copyWith(
                            fontSize: 33,
                            height: 1.14,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              const HomeArtworkIcon(HomeArtwork.wave,
                  size: 27, color: BingoPalette.primary),
            ]),
          ],
        ),
      ),
    );
  }
}

class _GreetingStroke extends CustomPainter {
  const _GreetingStroke();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final y = size.height;
    final stroke = Path()
      ..moveTo(0, y)
      ..cubicTo(w * .21, y - 3.4, w * .5, y - 6, w * .78, y - 5.1)
      ..quadraticBezierTo(w * .91, y - 4.9, w, y - 3.9)
      ..cubicTo(w * .65, y - 4.1, w * .31, y - 1.5, 0, y + .7)
      ..close();
    canvas.drawPath(
        stroke,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0xFFF887AC),
              BingoPalette.primary,
              Color(0xFFFBA4BF)
            ],
          ).createShader(Rect.fromLTWH(0, y - 6, w, 7)));
  }

  @override
  bool shouldRepaint(covariant _GreetingStroke oldDelegate) => false;
}
