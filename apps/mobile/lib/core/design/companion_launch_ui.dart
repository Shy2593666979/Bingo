import 'package:flutter/material.dart';
import 'package:bingo/core/theme/app_theme.dart';

/// Shared visual language for the main companion screens.
abstract final class CompanionLaunch {
  static const ink = BingoPalette.ink;
  static const muted = BingoPalette.muted;
  static const primary = BingoPalette.primary;
  static const line = BingoPalette.line;
  static const tint = BingoPalette.softSurface;
  static const icon = BingoPalette.primary;
  static const background = BoxDecoration(color: Colors.white);
  static bool compact(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= 380;
  static bool narrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= 335;
  static TextStyle text(double size,
          {Color color = ink,
          FontWeight weight = FontWeight.w400,
          double height = 1.35}) =>
      BingoTypography.body.copyWith(
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: 0,
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
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 7, horizontalPadding, 7),
      child: SizedBox(
          height: 42,
          child: Row(children: [
            Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CompanionLaunch.text(18, weight: FontWeight.w600))),
            for (final action in actions)
              SizedBox(width: 42, height: 42, child: action),
          ])),
    );
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
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CompanionLaunch.line))),
        child: Row(children: [
          for (final tab in tabs)
            Expanded(
                child: Semantics(
              button: true,
              selected: selected == tab.value,
              child: InkWell(
                onTap: () => onSelected(tab.value),
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                    height: 46,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                            child: Center(
                                child: Text(tab.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: CompanionLaunch.text(15,
                                        weight: selected == tab.value
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: selected == tab.value
                                            ? CompanionLaunch.ink
                                            : CompanionLaunch.muted)))),
                        AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 22,
                            height: 3,
                            decoration: BoxDecoration(
                                color: selected == tab.value
                                    ? CompanionLaunch.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(2))),
                      ],
                    )),
              ),
            )),
        ]),
      );
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
          color: enabled ? CompanionLaunch.primary : BingoPalette.softSurface,
          borderRadius: BorderRadius.circular(22)),
      child: TextButton(
          onPressed: enabled ? onPressed : null,
          style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: CompanionLaunch.muted,
              minimumSize: const Size(0, 27),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: CompanionLaunch.text(12,
                  color: Colors.white, weight: FontWeight.w500)),
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
        color: group ? const Color(0xFFF1F4F7) : BingoPalette.softSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), side: BorderSide.none),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: EdgeInsets.only(left: narrow ? 10 : 12, right: 8),
                child: Row(children: [
                  SizedBox.square(
                      dimension: narrow ? 26 : 32,
                      child: CustomPaint(painter: _LaunchCreateGlyph(group))),
                  SizedBox(width: compact ? 7 : 10),
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(group ? '创建群聊' : '创建搭子',
                            maxLines: 1,
                            style: CompanionLaunch.text(narrow ? 13 : 15,
                                color: BingoPalette.ink,
                                weight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(group ? '和伙伴们一起聊' : '一对一陪伴聊天',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CompanionLaunch.text(narrow ? 10 : 11,
                                color: BingoPalette.muted)),
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
