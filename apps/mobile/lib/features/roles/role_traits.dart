import 'dart:math' as math;
import 'package:flutter/material.dart';

const roleCategories = ['陪伴', '朋友', '恋人', '治愈', '成长', '生活'];
const roleTraits = <String, String>{
  '主动关心': 'heart',
  '温柔体贴': 'leaf',
  '陪伴聊天': 'chat',
  '阳光开朗': 'sun',
  '有趣好聊': 'chat',
  '兴趣同好': 'game',
  '善于倾听': 'heart',
  '情绪安抚': 'leaf',
  '温暖治愈': 'moon',
  '一起出行': 'plane',
  '生活分享': 'coffee',
  '积极向上': 'star',
  '贴心恋人': 'heart',
  '甜蜜互动': 'heart',
  '专属陪伴': 'moon',
  '学习督促': 'book',
  '一起成长': 'sprout',
  '正能量': 'star',
  '安心陪伴': 'shield',
  '耐心倾听': 'chat',
  '鼓励支持': 'star',
  '生活关怀': 'coffee',
  '暖心叮嘱': 'heart',
  '沉稳可靠': 'shield',
  '耐心讲解': 'book',
  '成长引导': 'sprout',
  '答疑解惑': 'bulb',
  '天马行空': 'star',
  '童真快乐': 'sun',
  '分享快乐': 'game',
  '工作搭子': 'coffee',
  '思路梳理': 'bulb',
  '高效协作': 'shield',
  '轻松幽默': 'sun',
  '旅行分享': 'plane',
  '音乐同好': 'music',
  '阅读交流': 'book',
  '安静陪伴': 'moon',
  '灵感碰撞': 'bulb',
  '运动伙伴': 'sun',
  '美食分享': 'coffee',
  '游戏搭子': 'game',
};

class TraitIcon extends StatelessWidget {
  const TraitIcon(this.kind, {this.size = 19, this.color, super.key});
  final String kind;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size, child: CustomPaint(painter: _TraitPainter(kind, color)));
}

class TraitBadge extends StatelessWidget {
  const TraitBadge(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: const Color(0xFFEDF8F5),
            borderRadius: BorderRadius.circular(24)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TraitIcon(roleTraits[label] ?? 'chat', size: 15),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF294C46))),
        ]),
      );
}

class _TraitPainter extends CustomPainter {
  const _TraitPainter(this.kind, this.color);
  final String kind;
  final Color? color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final color = this.color ??
        switch (kind) {
          'heart' => const Color(0xFFFF94AC),
          'sun' || 'moon' || 'star' || 'bulb' => const Color(0xFFFFC62E),
          'plane' || 'book' => const Color(0xFF47B6D2),
          'coffee' => const Color(0xFFAA9993),
          _ => const Color(0xFF119D83),
        };
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final white = Paint()..color = Colors.white;
    switch (kind) {
      case 'heart':
        canvas.drawPath(
            Path()
              ..moveTo(12, 22)
              ..cubicTo(7, 18, 1, 13, 1, 7)
              ..cubicTo(1, 1, 8, 0, 12, 5)
              ..cubicTo(16, 0, 23, 1, 23, 7)
              ..cubicTo(23, 13, 17, 18, 12, 22)
              ..close(),
            fill);
        canvas.drawOval(const Rect.fromLTWH(4, 4, 2, 5),
            Paint()..color = const Color(0x77FFFFFF));
      case 'leaf':
        canvas.drawPath(
            Path()
              ..moveTo(3, 20)
              ..cubicTo(1, 8, 10, 2, 22, 2)
              ..cubicTo(23, 14, 16, 20, 3, 20)
              ..close(),
            fill);
        canvas.drawPath(
            Path()
              ..moveTo(2, 23)
              ..quadraticBezierTo(7, 12, 19, 5),
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4);
      case 'chat':
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(1, 2, 22, 17), const Radius.circular(9)),
            fill);
        canvas.drawPath(
            Path()
              ..moveTo(5, 16)
              ..lineTo(3, 23)
              ..lineTo(12, 18)
              ..close(),
            fill);
        for (final horizontal in [7.0, 12.0, 17.0]) {
          canvas.drawCircle(Offset(horizontal, 10.5), 1.3, white);
        }
      case 'star':
        final path = Path();
        for (var index = 0; index < 10; index++) {
          final angle = -math.pi / 2 + index * math.pi / 5;
          final radius = index.isEven ? 11.5 : 5.6;
          final position = Offset(
              12 + math.cos(angle) * radius, 12 + math.sin(angle) * radius);
          if (index == 0) {
            path.moveTo(position.dx, position.dy);
          } else {
            path.lineTo(position.dx, position.dy);
          }
        }
        canvas.drawPath(path..close(), fill);
      case 'moon':
        canvas.drawPath(
            Path()
              ..moveTo(15, 1)
              ..cubicTo(-3, 0, -3, 24, 14, 23)
              ..cubicTo(20, 23, 23, 18, 23, 14)
              ..cubicTo(9, 20, 6, 8, 15, 1)
              ..close(),
            fill);
      case 'sun':
        canvas.drawCircle(const Offset(12, 12), 5.6, fill);
        for (var index = 0; index < 8; index++) {
          final angle = index * math.pi / 4;
          canvas.drawLine(
              Offset(12 + math.cos(angle) * 8, 12 + math.sin(angle) * 8),
              Offset(12 + math.cos(angle) * 11, 12 + math.sin(angle) * 11),
              stroke);
        }
      case 'plane':
        canvas.drawPath(
            Path()
              ..moveTo(1, 9)
              ..lineTo(10, 10)
              ..lineTo(19, 1)
              ..quadraticBezierTo(24, -1, 22, 4)
              ..lineTo(14, 13)
              ..lineTo(15, 23)
              ..lineTo(12, 22)
              ..lineTo(9, 16)
              ..lineTo(5, 20)
              ..lineTo(2, 19)
              ..lineTo(6, 13)
              ..lineTo(1, 11)
              ..close(),
            fill);
      case 'coffee':
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(2, 8, 16, 12), const Radius.circular(5)),
            fill);
        canvas.drawOval(const Rect.fromLTWH(15, 9, 7, 8), stroke);
        canvas.drawLine(const Offset(3, 22), const Offset(19, 22), stroke);
        canvas.drawPath(
            Path()
              ..moveTo(8, 5)
              ..quadraticBezierTo(5, 3, 8, 1)
              ..moveTo(13, 5)
              ..quadraticBezierTo(10, 3, 13, 1),
            stroke);
      case 'book':
        canvas.drawPath(
            Path()
              ..moveTo(2, 3)
              ..quadraticBezierTo(8, 1, 12, 5)
              ..quadraticBezierTo(16, 1, 22, 3)
              ..lineTo(22, 21)
              ..quadraticBezierTo(16, 19, 12, 23)
              ..quadraticBezierTo(8, 19, 2, 21)
              ..close(),
            fill);
        canvas.drawLine(
            const Offset(12, 5),
            const Offset(12, 21),
            Paint()
              ..color = Colors.white
              ..strokeWidth = 1.4);
      case 'sprout':
        canvas.drawLine(const Offset(12, 23), const Offset(12, 10), stroke);
        canvas.drawOval(const Rect.fromLTWH(2, 6, 10, 8), fill);
        canvas.drawOval(const Rect.fromLTWH(12, 1, 10, 10), fill);
        canvas.drawLine(const Offset(7, 23), const Offset(17, 23), stroke);
      case 'shield':
        canvas.drawPath(
            Path()
              ..moveTo(12, 1)
              ..lineTo(22, 5)
              ..lineTo(20, 15)
              ..quadraticBezierTo(18, 20, 12, 23)
              ..quadraticBezierTo(6, 20, 4, 15)
              ..lineTo(2, 5)
              ..close(),
            fill);
        canvas.drawPath(
            Path()
              ..moveTo(7, 12)
              ..lineTo(11, 16)
              ..lineTo(17, 8),
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      case 'bulb':
        canvas.drawCircle(const Offset(12, 9), 8, fill);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(8, 15, 8, 5), const Radius.circular(2)),
            fill);
        canvas.drawLine(const Offset(9, 23), const Offset(15, 23), stroke);
      case 'music':
        canvas.drawPath(
            Path()
              ..moveTo(8, 18)
              ..lineTo(8, 4)
              ..lineTo(21, 1)
              ..lineTo(21, 16)
              ..moveTo(8, 8)
              ..lineTo(21, 5),
            stroke);
        canvas.drawOval(const Rect.fromLTWH(1, 16, 8, 6), fill);
        canvas.drawOval(const Rect.fromLTWH(14, 14, 8, 6), fill);
      default:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(1, 6, 22, 15), const Radius.circular(6)),
            fill);
        final line = Paint()
          ..color = Colors.white
          ..strokeWidth = 2;
        canvas.drawLine(const Offset(5, 13), const Offset(11, 13), line);
        canvas.drawLine(const Offset(8, 10), const Offset(8, 16), line);
        canvas.drawCircle(const Offset(17, 11), 1.3, white);
        canvas.drawCircle(const Offset(19, 15), 1.3, white);
    }
  }

  @override
  bool shouldRepaint(_TraitPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
