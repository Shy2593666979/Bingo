import 'package:flutter/material.dart';
import 'package:bingo/core/theme/app_theme.dart';

/// Native components shared by the approved H2 screens.
class H2Categories extends StatelessWidget {
  const H2Categories(
      {required this.selected, required this.onSelected, super.key});
  final int selected;
  final ValueChanged<int> onSelected;
  static const labels = ['全部', '女友系', '男友系', '老师系', '工作搭子'];
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
              child: Semantics(
                  label: '分类${labels[i]}',
                  selected: selected == i,
                  button: true,
                  child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                          onTap: () => onSelected(i),
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 2),
                              child: Column(children: [
                                Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                        color: _color(i).withValues(alpha: .10),
                                        shape: BoxShape.circle),
                                    child: Icon(_icon(i),
                                        size: 21, color: _color(i))),
                                const SizedBox(height: 6),
                                Text(labels[i],
                                    maxLines: 1,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: selected == i
                                            ? BingoPalette.primary
                                            : BingoPalette.ink,
                                        fontWeight: selected == i
                                            ? FontWeight.w800
                                            : FontWeight.w500))
                              ]))))))
        ]
      ]);
  Color _color(int i) => [
        BingoPalette.primary,
        BingoPalette.rose,
        const Color(0xFF6487FA),
        BingoPalette.lavender,
        BingoPalette.muted
      ][i];
  IconData _icon(int i) => [
        Icons.stars_rounded,
        Icons.favorite_rounded,
        Icons.person_rounded,
        Icons.school_rounded,
        Icons.work_rounded
      ][i];
}

class H2Group extends StatelessWidget {
  const H2Group({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            const Divider(
                height: 1, indent: 16, endIndent: 16, color: BingoPalette.line),
          children[i]
        ]
      ]));
}
