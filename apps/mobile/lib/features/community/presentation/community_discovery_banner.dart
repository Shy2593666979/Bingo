import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';

class CommunityDiscoveryBanner extends StatelessWidget {
  const CommunityDiscoveryBanner({required this.onTap, super.key});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: BingoPalette.blush,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: SizedBox(
              height: 145.0 *
                  (MediaQuery.textScalerOf(context).scale(17) / 17)
                      .clamp(1.0, 3.0),
              child: LayoutBuilder(
                  builder: (_, size) => Stack(children: [
                        Positioned(
                            left: 15,
                            top: 14,
                            bottom: 14,
                            width: size.maxWidth * .61,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('发现有趣的 AI 搭子',
                                      style: TextStyle(
                                          fontSize: 18,
                                          height: 1.2,
                                          fontWeight: FontWeight.w800,
                                          color: refInk)),
                                  const SizedBox(height: 5),
                                  const Text('遇见同频的人设和故事',
                                      style: TextStyle(
                                          fontSize: 9, color: refMuted)),
                                  const Spacer(),
                                  ReferenceButton('去发现',
                                      small: true,
                                      icon: Icons.arrow_forward_rounded,
                                      onPressed: onTap)
                                ])),
                        Positioned(
                            right: 13,
                            top: 15,
                            child: Transform.rotate(
                                angle: .10, child: _portrait('男朋友'))),
                        Positioned(
                            right: 45,
                            bottom: 12,
                            child: Transform.rotate(
                                angle: -.10, child: _portrait('女朋友'))),
                      ])))));
  Widget _portrait(String role) => Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: BingoPalette.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1246583C), blurRadius: 12, offset: Offset(0, 4))
          ]),
      child: AssistantAvatar(role: role, size: 74));
}
