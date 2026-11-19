import 'dart:math' as math;
import 'package:flutter/material.dart';

class BubbleMessageAction {
  const BubbleMessageAction(this.value, this.label, this.icon);
  final String value, label;
  final IconData icon;
}

Future<String?> showBubbleMessageMenu(BuildContext context,
    {required Rect anchor,
    required Offset pressPosition,
    required List<BubbleMessageAction> actions}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭消息菜单',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, _, __) {
      final media = MediaQuery.of(context);
      final width = math.min(actions.length * 64.0 + 16, media.size.width - 24);
      const height = 75.0;
      final safeTop = media.padding.top + 8;
      final bottom = media.size.height -
          media.viewInsets.bottom -
          media.padding.bottom -
          8;
      final below = anchor.top - height - 8 < safeTop;
      final top = (below ? anchor.bottom + 8 : anchor.top - height - 8)
          .clamp(safeTop, math.max(safeTop, bottom - height))
          .toDouble();
      final left = (pressPosition.dx - width / 2)
          .clamp(12.0, media.size.width - width - 12)
          .toDouble();
      final arrowX =
          (pressPosition.dx - left - 6).clamp(12.0, width - 24).toDouble();
      return Stack(children: [
        Positioned(
            left: left,
            top: top,
            width: width,
            child: CustomPaint(
                painter: _MenuSurface(below, arrowX + 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (below) const SizedBox(height: 7),
                  Material(
                      key: const ValueKey('bubble-message-menu'),
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(children: [
                            for (final action in actions)
                              Expanded(
                                  child: InkWell(
                                      onTap: () =>
                                          Navigator.pop(context, action.value),
                                      child: SizedBox(
                                          height: 68,
                                          child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                CustomPaint(
                                                    size: const Size(23, 23),
                                                    painter: _MenuIcon(
                                                        action.value)),
                                                const SizedBox(height: 6),
                                                Text(action.label,
                                                    style: const TextStyle(
                                                        color:
                                                            Color(0xFF39363A),
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w400)),
                                              ])))),
                          ]))),
                  if (!below) const SizedBox(height: 7),
                ]))),
      ]);
    },
  );
}

class _MenuSurface extends CustomPainter {
  const _MenuSurface(this.up, this.arrowX);
  final bool up;
  final double arrowX;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, up ? 7 : 0, size.width, size.height - 7);
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14)));
    final base = up ? 7.5 : size.height - 7.5;
    final arrow = Path()
      ..moveTo(arrowX - 6, base)
      ..lineTo(arrowX, up ? .5 : size.height - .5)
      ..lineTo(arrowX + 6, base)
      ..close();
    final path = Path.combine(PathOperation.union, body, arrow);
    canvas.drawShadow(path, const Color(0x1F51434A), 7, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFDCD7DA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .65);
  }

  @override
  bool shouldRepaint(covariant _MenuSurface oldDelegate) =>
      up != oldDelegate.up || arrowX != oldDelegate.arrowX;
}

class _MenuIcon extends CustomPainter {
  const _MenuIcon(this.action);
  final String action;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = const Color(0xFF39363A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.55
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (action) {
      case 'copy':
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(8, 3, 12, 14), const Radius.circular(2.4)),
            paint);
        path.moveTo(4, 7);
        path.lineTo(4, 18.5);
        path.quadraticBezierTo(4, 21, 6.5, 21);
        path.lineTo(16, 21);
      case 'delete':
        path.moveTo(4, 6);
        path.lineTo(20, 6);
        path.moveTo(9, 3);
        path.lineTo(15, 3);
        path.moveTo(6, 9);
        path.lineTo(7, 19);
        path.quadraticBezierTo(7.2, 21, 9.2, 21);
        path.lineTo(14.8, 21);
        path.quadraticBezierTo(16.8, 21, 17, 19);
        path.lineTo(18, 9);
      case 'reply':
        path.moveTo(14, 4);
        path.lineTo(21, 10);
        path.lineTo(14, 16);
        path.lineTo(14, 12);
        path.cubicTo(8, 12, 5, 14, 3, 19);
        path.cubicTo(3.5, 11, 7, 7, 14, 8);
        path.close();
      case 'transcribe':
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(2, 3, 20, 18), const Radius.circular(3.5)),
            paint);
        path.moveTo(5, 8);
        path.lineTo(12, 8);
        path.moveTo(8.5, 6);
        path.lineTo(8.5, 8);
        path.moveTo(11, 8);
        path.quadraticBezierTo(10, 13, 6, 15);
        path.moveTo(6.5, 10);
        path.quadraticBezierTo(8, 13, 11, 14.5);
        path.moveTo(12.5, 16);
        path.lineTo(15.8, 8.5);
        path.lineTo(19, 16);
        path.moveTo(14, 13.5);
        path.lineTo(17.5, 13.5);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MenuIcon oldDelegate) =>
      action != oldDelegate.action;
}
