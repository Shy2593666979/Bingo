import 'package:bingo/core/design/release_ui.dart';
import 'package:bingo/core/design/bingo_surface.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/group_avatar.dart';
import 'package:flutter/material.dart';

class CreateCenterPage extends StatelessWidget {
  const CreateCenterPage(
      {required this.onCreateRole,
      required this.onCreateGroup,
      required this.onPublish,
      this.onDestination,
      super.key});
  final Future<void> Function() onCreateRole, onCreateGroup, onPublish;
  final ValueChanged<int>? onDestination;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        bottomNavigationBar: onDestination == null
            ? null
            : ReferenceNavigation(
                selected: -1,
                creating: true,
                onSelected: onDestination!,
                onCreate: () {}),
        body: DefaultTextStyle.merge(
            style: const TextStyle(letterSpacing: 0, height: 1.5),
            child: SafeArea(
                bottom: false,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                    children: [
                      ReleasePlainHeader('创建',
                          leading: onDestination == null
                              ? BackButton(
                                  onPressed: () => Navigator.maybePop(context))
                              : null),
                      const SizedBox(height: 6),
                      const Text('把一点灵感，变成一份陪伴。',
                          style: TextStyle(
                              fontSize: 13, color: BingoPalette.muted)),
                      const SizedBox(height: 24),
                      BingoSurface(
                          radius: 16,
                          padding: const EdgeInsets.fromLTRB(20, 20, 10, 17),
                          onTap: onCreateRole,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text('创建一个专属搭子',
                                                style: TextStyle(
                                                    fontSize: 22,
                                                    letterSpacing: -.5,
                                                    height: 1.45,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            SizedBox(height: 10),
                                            Text('定制性格与声音\n把想象中的陪伴带到身边。',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    height: 1.7,
                                                    color: BingoPalette.muted)),
                                          ])),
                                      SizedBox(width: 10),
                                      AssistantAvatar(role: '女朋友', size: 100),
                                    ]),
                                const SizedBox(height: 18),
                                FilledButton(
                                    onPressed: onCreateRole,
                                    style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 42),
                                        backgroundColor: BingoPalette.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 17),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        textStyle: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('开始创建'),
                                          SizedBox(width: 12),
                                          Icon(Icons.arrow_forward_rounded,
                                              size: 18),
                                        ])),
                              ])),
                      const SizedBox(height: 14),
                      _entry(
                          title: '创建群聊',
                          description: '和喜欢的搭子一起聊聊',
                          art: const GroupAvatar.roles(
                              ['女朋友', '男朋友', '老师', '同事'],
                              size: 48),
                          onTap: onCreateGroup),
                      const SizedBox(height: 14),
                      _entry(
                          title: '分享搭子',
                          description: '分享人设与故事，让陪伴被看见',
                          art: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                  color: BingoPalette.blush,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.near_me_outlined,
                                  color: BingoPalette.primary, size: 25)),
                          onTap: onPublish),
                      const SizedBox(height: 24),
                      const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.lightbulb_outline_rounded,
                                    size: 18, color: BingoPalette.muted),
                                SizedBox(width: 8),
                                Expanded(
                                    child: Text('灵感从一句话开始，陪伴由你定义。',
                                        style: TextStyle(
                                            fontSize: 12,
                                            height: 1.6,
                                            color: BingoPalette.muted))),
                              ])),
                    ]))),
      );

  Widget _entry(
          {required String title,
          required String description,
          required Widget art,
          required VoidCallback onTap}) =>
      BingoSurface(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          onTap: onTap,
          child: Row(children: [
            art,
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: BingoPalette.muted)),
                ])),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: BingoPalette.muted),
          ]));
}
