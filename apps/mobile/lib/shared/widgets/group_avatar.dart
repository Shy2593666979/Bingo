import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';

/// Keeps the same group identity in the message list and conversation header.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({required this.members, this.size = 48, super.key})
      : roleNames = null;
  const GroupAvatar.roles(this.roleNames, {this.size = 48, super.key})
      : members = const [];
  final List<GroupPerson> members;
  final List<String>? roleNames;
  final double size;
  static const _rows = <List<int>>[
    [],
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
  @override
  Widget build(BuildContext context) {
    final people = (roleNames ??
            members
                .where((member) => member.active)
                .map((member) => member.roleName)
                .toList())
        .take(9)
        .toList();
    final count = people.length;
    final gap = size * .025;
    final padding = size * .035;
    final columns = count <= 4 ? 2 : 3;
    final cell = (size - padding * 2 - gap * (columns - 1)) / columns;
    final rows = _rows[count];
    final height = rows.length * cell + (rows.length - 1) * gap;
    var index = 0;
    final tiles = <Widget>[];
    for (var row = 0; row < rows.length; row++) {
      final width = rows[row] * cell + (rows[row] - 1) * gap;
      for (var column = 0; column < rows[row]; column++) {
        final personIndex = index++;
        tiles.add(Positioned(
          key: ValueKey('group-avatar-tile-$personIndex'),
          left: (size - width) / 2 + column * (cell + gap),
          top: (size - height) / 2 + row * (cell + gap),
          width: cell,
          height: cell,
          child: AvatarFrame(
              size: cell,
              cornerRadius: cell * .08,
              color: const Color(0xFFF4FBF7),
              child: AssistantAvatar(
                  role: people[personIndex],
                  size: cell,
                  cornerRadius: cell * .08)),
        ));
      }
    }
    return AvatarFrame(
        size: size,
        color: const Color(0xFFEDF7F2),
        child: Stack(children: tiles));
  }
}
