import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle(this.title, {required this.style});
  final String title;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.centerLeft,
      child: Stack(children: [
        Positioned.fill(
            bottom: 2,
            child: IgnorePointer(
                child: Align(
                    alignment: Alignment.bottomRight,
                    child: FractionallySizedBox(
                        widthFactor: .37,
                        child: Transform.rotate(
                            angle: -.05236,
                            child: Container(
                                height: 7,
                                decoration: const BoxDecoration(
                                    color: Color(0x806DDBA0),
                                    borderRadius: BorderRadius.all(
                                        Radius.elliptical(100, 50))))))))),
        Text(title, style: style),
      ]));
}

class ReleasePlainHeader extends StatelessWidget {
  const ReleasePlainHeader(this.title,
      {this.leading, this.actions = const [], super.key});
  final String title;
  final Widget? leading;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 70,
      child: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(children: [
            if (leading != null)
              SizedBox(width: 38, height: 40, child: leading),
            Expanded(
                child: _HeaderTitle(title,
                    style: const TextStyle(
                        fontSize: 25,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.7))),
            for (final action in actions)
              SizedBox(width: 38, height: 40, child: action),
          ])));
}

class ReleasePageHeader extends StatelessWidget {
  const ReleasePageHeader(this.title, {this.actions = const [], super.key});
  final String title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 17, 0, 16),
      child: Row(children: [
        Expanded(
            child: _HeaderTitle(title,
                style: const TextStyle(
                    fontSize: 24, height: 1.3, fontWeight: FontWeight.w600))),
        for (final action in actions)
          SizedBox(width: 38, height: 40, child: action),
      ]));
}

class ReleaseSegmentedTabs extends StatelessWidget {
  const ReleaseSegmentedTabs(
      {required this.tabs,
      required this.selected,
      required this.onSelected,
      super.key});
  final List<({int value, String label})> tabs;
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: const Color(0xFFECF2EF),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (final tab in tabs)
          Expanded(
              child: Semantics(
                  selected: tab.value == selected,
                  button: true,
                  label: tab.label,
                  child: Material(
                      color: tab.value == selected
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                          onTap: () => onSelected(tab.value),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 7),
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(tab.label,
                                      maxLines: 1,
                                      style: TextStyle(
                                          fontSize: 12,
                                          height: 1.5,
                                          fontWeight: tab.value == selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: tab.value == selected
                                              ? BingoPalette.ink
                                              : BingoPalette.muted))))))))
      ]));
}
