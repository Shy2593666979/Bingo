import 'package:bingo/core/design/home_artwork_icon.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/theme/home_palette.dart';
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
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$greeting，',
                    style: BingoTypography.sectionTitle.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF4A4248))),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: CustomPaint(
                      painter: const _GreetingStroke(),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(name,
                            style: BingoTypography.sectionTitle.copyWith(
                                fontSize: 26,
                                height: 1.18,
                                fontWeight: FontWeight.w700,
                                color: HomePalette.ink)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const HomeArtworkIcon(HomeArtwork.wave,
                      size: 22, color: HomePalette.accent),
                ]),
              ],
            ),
            const SizedBox(height: 4),
            const Text('在这里慢慢聊，搭子一直都在',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: HomePalette.muted)),
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
    final y = size.height - 1;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - 3.5, w, 3.5),
      const Radius.circular(3),
    );
    canvas.drawRRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0x66ED82A4),
              Color(0xB3DC5E84),
              Color(0x44F3B0C5),
            ],
          ).createShader(Rect.fromLTWH(0, y - 3.5, w, 3.5)));
  }

  @override
  bool shouldRepaint(covariant _GreetingStroke oldDelegate) => false;
}
