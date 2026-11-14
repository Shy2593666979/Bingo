import 'dart:math' as math;
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';

class GroupAvatar extends StatelessWidget {
  const GroupAvatar({required this.members, this.size = 48, super.key})
      : roleNames = null;
  const GroupAvatar.roles(this.roleNames, {this.size = 48, super.key})
      : members = const [];
  final List<GroupPerson> members;
  final List<String>? roleNames;
  final double size;
  List<Rect> _layout(int count) {
    if (count == 0) return [];
    if (count == 1) return [const Rect.fromLTWH(0, 0, 1, 1)];
    const arrangements = [
      [1],
      [2],
      [1, 2],
      [2, 2],
      [2, 3],
      [3, 3],
      [1, 3, 3],
      [2, 3, 3],
      [3, 3, 3],
    ];
    final rows = arrangements[count - 1];
    final columns = rows.reduce(math.max);
    const padding = .035;
    const gap = .025;
    final extent = (1 - 2 * padding - (columns - 1) * gap) / columns;
    final top = (1 - rows.length * extent - (rows.length - 1) * gap) / 2;
    return [
      for (var row = 0; row < rows.length; row++)
        for (var column = 0; column < rows[row]; column++)
          Rect.fromLTWH(
            (1 - rows[row] * extent - (rows[row] - 1) * gap) / 2 +
                column * (extent + gap),
            top + row * (extent + gap),
            extent,
            extent,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final people = (roleNames ??
            members.where((m) => m.active).map((m) => m.roleName).toList())
        .take(9)
        .toList();
    final boxes = _layout(people.length);
    return AvatarFrame(
        size: size,
        color: BingoPalette.softSurface,
        child: people.isEmpty
            ? const Center(child: Icon(Icons.groups_outlined))
            : Stack(children: [
                for (var i = 0; i < people.length; i++)
                  Positioned(
                    key: ValueKey('group-avatar-tile-$i'),
                    left: boxes[i].left * size,
                    top: boxes[i].top * size,
                    width: boxes[i].width * size,
                    height: boxes[i].height * size,
                    child:
                        ClipRect(child: LayoutBuilder(builder: (context, box) {
                      final extent = math.max(box.maxWidth, box.maxHeight);
                      return OverflowBox(
                          minWidth: extent,
                          maxWidth: extent,
                          minHeight: extent,
                          maxHeight: extent,
                          child: AssistantAvatar(
                              role: people[i],
                              size: extent,
                              cornerRadius: 0,
                              closePortrait: const {
                                '女朋友',
                                '男朋友',
                                '同事',
                                '老师',
                                '邻家大叔',
                                '弟弟',
                                '闺蜜',
                                '好兄弟',
                                '学姐',
                                '学长',
                                '树洞搭子',
                                '运动搭子'
                              }.contains(people[i])));
                    })),
                  )
              ]));
  }
}
