import 'package:flutter/material.dart';
import 'package:bingo/core/design/bingo_wordmark.dart';

/// The approved E layout with D colors. Scoped to the four primary screens.
abstract final class CompanionLaunch {
  static const ink = Color(0xFF15271C);
  static const muted = Color(0xFF718777);
  static const primary = Color(0xFF00A786);
  static const line = Color(0xFFE9F0EB);
  static const tint = Color(0xFFEFFAF3);
  static const icon = Color(0xFF65AD94);
  static const background = BoxDecoration(
      gradient: RadialGradient(
          center: Alignment(1, 0),
          radius: 1.3,
          colors: [Color(0xFFF8FEFA), Colors.white]));
  static bool compact(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= 380;
  static bool narrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= 335;
  static TextStyle text(double size,
          {Color color = ink,
          FontWeight weight = FontWeight.w400,
          double height = 1.5}) =>
      TextStyle(
          fontFamily: 'BingoSans',
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color);
}

class CompanionLaunchHeader extends StatelessWidget {
  const CompanionLaunchHeader(this.title,
      {this.actions = const [], this.horizontalPadding = 15, super.key});
  final String title;
  final List<Widget> actions;
  final double horizontalPadding;
  @override
  Widget build(BuildContext context) {
    final compact = CompanionLaunch.compact(context);
    final narrow = CompanionLaunch.narrow(context);
    return SizedBox(
        height: 69,
        child: Padding(
            padding: EdgeInsets.fromLTRB(
                horizontalPadding, 17, horizontalPadding, 16),
            child: Row(children: [
              BingoWordmark(
                  width: narrow
                      ? 77
                      : compact
                          ? 85
                          : 93,
                  height: narrow
                      ? 31
                      : compact
                          ? 33
                          : 36),
              SizedBox(width: narrow ? 7 : 9),
              Container(width: 1, height: 22, color: const Color(0xFFD6DFD8)),
              SizedBox(
                  width: narrow
                      ? 11
                      : compact
                          ? 13
                          : 17),
              Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CompanionLaunch.text(
                          narrow
                              ? 18
                              : compact
                                  ? 20
                                  : 22,
                          weight: FontWeight.w700,
                          height: 1.2))),
              for (final action in actions)
                Padding(
                    padding: const EdgeInsets.only(left: 9),
                    child: SizedBox(width: 32, height: 36, child: action)),
            ])));
  }
}

class CompanionLaunchTabs extends StatelessWidget {
  const CompanionLaunchTabs(
      {required this.tabs,
      required this.selected,
      required this.onSelected,
      super.key});
  final List<({int value, String label})> tabs;
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 3, 22, 9),
      child: Row(children: [
        for (final tab in tabs)
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Semantics(
                      button: true,
                      selected: selected == tab.value,
                      child: Material(
                          color: selected == tab.value
                              ? const Color(0xFFE7F8EE)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(23),
                          child: InkWell(
                              borderRadius: BorderRadius.circular(23),
                              onTap: () => onSelected(tab.value),
                              child: SizedBox(
                                  height: 36,
                                  child: Center(
                                      child: Text(tab.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: CompanionLaunch.text(
                                              CompanionLaunch.narrow(context)
                                                  ? 14
                                                  : 16,
                                              weight: selected == tab.value
                                                  ? FontWeight.w700
                                                  : FontWeight.w400,
                                              color: selected == tab.value
                                                  ? CompanionLaunch.primary
                                                  : const Color(
                                                      0xFF6F8274))))))))))
      ]));
}

class CompanionLaunchButton extends StatelessWidget {
  const CompanionLaunchButton(
      {required this.label,
      required this.onPressed,
      this.enabled = true,
      super.key});
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF0ABD94), CompanionLaunch.primary])
              : null,
          color: enabled ? null : const Color(0xFFEDF5EF),
          borderRadius: BorderRadius.circular(19)),
      child: TextButton(
          onPressed: enabled ? onPressed : null,
          style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: CompanionLaunch.muted,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: CompanionLaunch.text(
                  CompanionLaunch.compact(context) ? 12 : 14,
                  color: Colors.white,
                  weight: FontWeight.w500)),
          child: Text(label)));
}

class CompanionLaunchCreateAction extends StatelessWidget {
  const CompanionLaunchCreateAction(
      {required this.group, required this.onTap, super.key});
  final bool group;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final compact = CompanionLaunch.compact(context);
    final narrow = CompanionLaunch.narrow(context);
    return Material(
        color: group ? const Color(0xFFF0FBF5) : const Color(0xFFF3FCF7),
        borderRadius: BorderRadius.circular(21),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: EdgeInsets.only(
                    left: narrow
                        ? 10
                        : compact
                            ? 14
                            : 20,
                    right: 4),
                child: Row(children: [
                  SizedBox.square(
                      dimension: narrow
                          ? 32
                          : compact
                              ? 38
                              : 44,
                      child: CustomPaint(painter: _LaunchCreateGlyph(group))),
                  SizedBox(width: compact ? 7 : 10),
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(group ? '创建群聊' : '创建搭子',
                            maxLines: 1,
                            style: CompanionLaunch.text(
                                narrow
                                    ? 14
                                    : compact
                                        ? 16
                                        : 18,
                                color: const Color(0xFF3C6551),
                                weight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(group ? '和伙伴们一起聊' : '一对一陪伴聊天',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CompanionLaunch.text(
                                narrow
                                    ? 10
                                    : compact
                                        ? 12
                                        : 14,
                                color: const Color(0xFF7D9788))),
                      ])),
                ]))));
  }
}

class _LaunchCreateGlyph extends CustomPainter {
  const _LaunchCreateGlyph(this.group);
  final bool group;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 30);
    canvas.translate(3, 3);
    final stroke = Paint()
      ..color = CompanionLaunch.icon
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.45
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(Offset(group ? 8.5 : 9, 6.5), group ? 3.3 : 3.5, stroke);
    canvas.drawPath(
        Path()
          ..moveTo(2, 21)
          ..lineTo(2, 18)
          ..cubicTo(2, 14.5, 4.8, 12.5, group ? 8.5 : 9, 12.5)
          ..cubicTo(13.2, 12.5, group ? 15 : 16, 14.5, group ? 15 : 16, 18)
          ..lineTo(group ? 15 : 16, 21)
          ..close(),
        stroke);
    if (group) {
      canvas.drawCircle(const Offset(18, 7.5), 2.7, stroke);
      canvas.drawPath(
          Path()
            ..moveTo(17, 13)
            ..cubicTo(20.4, 13.1, 22, 14.8, 22, 17.5)
            ..lineTo(22, 21)
            ..lineTo(17.5, 21),
          stroke);
    } else {
      canvas.drawLine(const Offset(20, 7), const Offset(20, 15), stroke);
      canvas.drawLine(const Offset(16, 11), const Offset(24, 11), stroke);
    }
  }

  @override
  bool shouldRepaint(_LaunchCreateGlyph oldDelegate) =>
      group != oldDelegate.group;
}
