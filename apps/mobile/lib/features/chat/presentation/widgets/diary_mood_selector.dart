import 'package:flutter/material.dart';

class DiaryMoodSelector extends StatelessWidget {
  const DiaryMoodSelector(
      {required this.value, required this.onChanged, super.key});

  static const moods = ['很开心', '还不错', '有点累', '不太好'];
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var index = 0; index < moods.length; index++) ...[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
              child: Semantics(
                  label: moods[index],
                  button: true,
                  selected: value == moods[index],
                  enabled: onChanged != null,
                  child: ExcludeSemantics(
                      child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                              key: ValueKey('diary-mood-${moods[index]}'),
                              borderRadius: BorderRadius.circular(17),
                              onTap: onChanged == null
                                  ? null
                                  : () => onChanged!(moods[index]),
                              child: Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(2, 12, 2, 9),
                                  decoration: BoxDecoration(
                                      color: value == moods[index]
                                          ? const Color(0xFFEDF6EF)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(17),
                                      border: Border.all(
                                          color: value == moods[index]
                                              ? const Color(0xFFB4CEBE)
                                              : Colors.transparent)),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Opacity(
                                            opacity:
                                                value == moods[index] ? 1 : .82,
                                            child: CustomPaint(
                                                size: const Size.square(38),
                                                painter: _MoodPainter(index))),
                                        const SizedBox(height: 9),
                                        Text(moods[index],
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: value == moods[index]
                                                    ? const Color(0xFF3E7058)
                                                    : const Color(0xFF73887D),
                                                fontWeight:
                                                    value == moods[index]
                                                        ? FontWeight.w600
                                                        : FontWeight.w400)),
                                      ]))))))),
        ],
      ]);
}

class _MoodPainter extends CustomPainter {
  const _MoodPainter(this.index);
  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 40);
    const fills = [
      Color(0xFFFFF1C9),
      Color(0xFFE1F2E8),
      Color(0xFFEEE9F5),
      Color(0xFFE5EFF8)
    ];
    const edges = [
      Color(0xFFB69954),
      Color(0xFF56856A),
      Color(0xFF9482A9),
      Color(0xFF7C9FB4)
    ];
    final fill = Paint()..color = fills[index];
    final stroke = Paint()
      ..color = edges[index]
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(const Offset(20, 20), 18, fill);
    final face = Path();
    switch (index) {
      case 0:
        face
          ..moveTo(12, 17)
          ..quadraticBezierTo(14.5, 13.5, 17, 17)
          ..moveTo(23, 17)
          ..quadraticBezierTo(25.5, 13.5, 28, 17);
        stroke.strokeWidth = 1.8;
        final mouth = Path()
          ..moveTo(15, 23)
          ..quadraticBezierTo(20, 24.5, 25, 23)
          ..cubicTo(24.5, 26.5, 22.7, 28.5, 20, 28.5)
          ..cubicTo(17.3, 28.5, 15.5, 26.5, 15, 23)
          ..close();
        canvas.drawPath(mouth, Paint()..color = const Color(0xFFA48A57));
      case 1:
        final eyes = Paint()..color = edges[index];
        canvas.drawCircle(const Offset(14.5, 17), 1.3, eyes);
        canvas.drawCircle(const Offset(25.5, 17), 1.3, eyes);
        face
          ..moveTo(16, 24)
          ..quadraticBezierTo(20, 28, 24, 24);
        stroke.strokeWidth = 1.8;
      case 2:
        face
          ..moveTo(10, 17)
          ..quadraticBezierTo(13, 20, 16, 17)
          ..moveTo(24, 17)
          ..quadraticBezierTo(27, 20, 30, 17)
          ..moveTo(27, 7)
          ..lineTo(32, 7)
          ..lineTo(27, 12)
          ..lineTo(32, 12);
        canvas.drawOval(const Rect.fromLTWH(17.5, 24, 5, 6), stroke);
      case 3:
        face
          ..moveTo(10, 13)
          ..lineTo(16, 15)
          ..moveTo(24, 15)
          ..lineTo(30, 13)
          ..moveTo(13, 18)
          ..lineTo(13, 20)
          ..moveTo(27, 18)
          ..lineTo(27, 20)
          ..moveTo(14, 28)
          ..quadraticBezierTo(20, 22, 26, 28);
        final tear = Path()
          ..moveTo(31, 20)
          ..quadraticBezierTo(27, 25, 31, 25)
          ..quadraticBezierTo(35, 25, 31, 20)
          ..close();
        canvas.drawPath(tear, Paint()..color = const Color(0xFFA6C9DF));
    }
    canvas.drawPath(face, stroke);
    if (index < 2) {
      final cheek = Paint()
        ..color = const Color(0xFFEAA3A0).withValues(alpha: .32);
      canvas.drawOval(const Rect.fromLTWH(7.5, 20.5, 5, 3), cheek);
      canvas.drawOval(const Rect.fromLTWH(27.5, 20.5, 5, 3), cheek);
    }
  }

  @override
  bool shouldRepaint(covariant _MoodPainter oldDelegate) =>
      oldDelegate.index != index;
}
