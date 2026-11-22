import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

/// A persisted call receipt, distinct from conversational system notices.
class GroupCallMessageCard extends StatelessWidget {
  const GroupCallMessageCard(
      {required this.record,
      required this.members,
      this.userAvatarData,
      this.username = '',
      super.key});
  final Map<String, dynamic> record;
  final List<GroupPerson> members;
  final String? userAvatarData;
  final String username;

  @override
  Widget build(BuildContext context) {
    final seconds = (record['duration_seconds'] as num? ?? 0).toInt();
    final connected = record['status'] == 'completed';
    final duration =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final people =
        (record['participants'] as List? ?? []).whereType<Map>().toList();
    final count = (record['participant_count'] as num? ?? 0).toInt();
    final invited = (record['invited_count'] as num? ?? people.length).toInt();
    final status = connected ? '通话已结束' : '未接通';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Material(
        color: BingoPalette.userBubble,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17),
                topRight: Radius.circular(17),
                bottomLeft: Radius.circular(17),
                bottomRight: Radius.circular(4)),
            side: const BorderSide(color: Color(0xFFD7E6C8))),
        child: InkWell(
          onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                      title: const Text('群聊语音通话'),
                      content: Text(
                          '你发起 · $status\n${connected ? '通话时长 $duration\n$count 人参与' : '邀请 $invited 位搭子'}${people.isEmpty ? '' : '\n${[
                              ...people.map((p) => p['name']),
                              if (connected) username.isEmpty ? '我' : username
                            ].join('、')}'}'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('知道了'))
                      ])),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
                child: Row(children: [
                  Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                          color: Color(0x80FFFFFF), shape: BoxShape.circle),
                      child: Icon(
                          connected
                              ? Icons.call_outlined
                              : Icons.call_end_outlined,
                          size: 18,
                          color: const Color(0xFF526746))),
                  const SizedBox(width: 9),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('群聊语音通话',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: BingoPalette.ink)),
                        const SizedBox(height: 4),
                        Text('你发起 · $status',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF7E8C72))),
                      ])),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: Color(0xFF879B77)),
                ])),
            Container(
                color: const Color(0x55FFFFFF),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
                child: Row(children: [
                  Expanded(
                      child: Wrap(
                          spacing: 3,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                        ...people.map((person) {
                          final member = members
                              .where((m) => m.id == person['id'])
                              .firstOrNull;
                          return ClipRRect(
                              key: ValueKey(
                                  'group-call-participant-${person['id']}'),
                              borderRadius: BorderRadius.circular(7),
                              child: AssistantAvatar(
                                  role: member?.roleName, size: 24));
                        }),
                        if (connected && people.isNotEmpty)
                          UserAvatar(
                              key:
                                  const ValueKey('group-call-participant-user'),
                              avatarData: userAvatarData,
                              username: username,
                              size: 24),
                        Text(connected ? '$count 人参与' : '邀请 $invited 位搭子',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF7E8C72))),
                      ])),
                  Text(connected ? duration : '未产生通话',
                      style: TextStyle(
                          fontSize: connected ? 23 : 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF43523A))),
                ])),
          ]),
        ),
      ),
    );
  }
}
