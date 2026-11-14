import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An asset cover represents a voice, never the portrait of a linked companion.
class VoiceCover extends StatelessWidget {
  const VoiceCover(
      {required this.id,
      this.size = 56,
      this.playing = false,
      this.showPlay = false,
      super.key});
  final String id;
  final double size;
  final bool playing, showPlay;
  static const _tones = [
    [Color(0xFF164C4C), Color(0xFF64908A), Color(0xFFE4CEAF)],
    [Color(0xFF143548), Color(0xFF476A7E), Color(0xFFE5DBC8)],
    [Color(0xFFB87920), Color(0xFFDFAD58), Color(0xFFF2E4C8)],
    [Color(0xFFA35551), Color(0xFFD89382), Color(0xFFF1DDCB)],
  ];
  @override
  Widget build(BuildContext context) {
    final seed = id.codeUnits.fold<int>(0, (a, b) => a * 31 + b) & 0x7fffffff;
    final colors = _tones[seed % _tones.length];
    return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * .22),
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors)),
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
              child: CustomPaint(painter: _VoiceMarble(seed, colors))),
          Icon(
              showPlay
                  ? (playing ? Icons.stop_rounded : Icons.play_arrow_rounded)
                  : Icons.graphic_eq_rounded,
              color: Colors.white.withValues(alpha: .95),
              size: size * .42),
        ]));
  }
}

/// Original fluid contours, generated from the voice ID without external art.
class _VoiceMarble extends CustomPainter {
  const _VoiceMarble(this.seed, this.colors);
  final int seed;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final phase = (seed % 37) / 8;
    for (var i = -6; i < 20; i++) {
      final y = i / 12;
      final drift = math.sin(i * .65 + phase) * .11;
      final path = Path()
        ..moveTo(-.2, y)
        ..cubicTo(.22, y + .52 + drift, .31, y - .31, .65, y + .17)
        ..cubicTo(.84, y + .44 + drift, .93, y + .12, 1.2, y + .48);
      canvas.drawPath(
          path,
          Paint()
            ..color = colors[i.abs() % 3].withValues(alpha: .8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .05 + (i.abs() % 4) * .025);
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFF2E4CF).withValues(alpha: .65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .003);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VoiceMarble oldDelegate) => oldDelegate.seed != seed;
}
