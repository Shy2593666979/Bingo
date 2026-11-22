import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:flutter/material.dart';
import 'package:bingo/core/role_avatar_store.dart';

String assistantAvatarAsset(String? role) => switch (role) {
      '男朋友' => 'assets/images/boyfriend.png',
      '女朋友' => 'assets/images/girlfriend.png',
      '家长' || '邻家大叔' => 'assets/images/parent.png',
      '老师' || '导师' => 'assets/images/teacher.png',
      '弟弟' || '小朋友' || '小孩' || '儿子' || '女儿' => 'assets/images/child.png',
      '同事' || '朋友' => 'assets/images/colleague.png',
      '闺蜜' => 'assets/images/bestie.png',
      '好兄弟' => 'assets/images/bro.png',
      '学姐' => 'assets/images/senior_sister.png',
      '学长' => 'assets/images/senior_brother.png',
      '知己' || '树洞搭子' => 'assets/images/confidant.png',
      '运动搭子' => 'assets/images/fitness.png',
      '董事长' => 'assets/images/chairman.png',
      '公司高管' => 'assets/images/executive.png',
      '网红人物' => 'assets/images/xiaofan.png',
      _ => 'assets/images/bingo_logo.png',
    };

class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({
    required this.role,
    required this.size,
    this.showOnline = false,
    this.cornerRadius,
    this.closePortrait = false,
    this.onlineDotSize,
    this.onlineBorderWidth = 1.5,
    super.key,
  });

  final String? role;
  final double size;
  final bool showOnline;
  final double? cornerRadius;
  final bool closePortrait;
  final double? onlineDotSize;
  final double onlineBorderWidth;

  Widget _asset() => Image.asset(
      squareAvatarAsset(
          RoleAvatarStore.assets[role] ?? assistantAvatarAsset(role)),
      fit: BoxFit.cover,
      cacheWidth: 512,
      cacheHeight: 512,
      errorBuilder: (_, __, ___) =>
          Image.asset('assets/images/bingo_logo.webp', fit: BoxFit.cover));

  @override
  Widget build(BuildContext context) {
    final dotSize = onlineDotSize ?? size * 0.17;
    return SizedBox.square(
      dimension: size + (showOnline ? dotSize * 0.18 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ListenableBuilder(
              listenable: Listenable.merge(
                  [RoleAvatarStore.images, RoleAvatarStore.backgrounds]),
              builder: (context, _) {
                final uploaded = RoleAvatarStore.images.value[role];
                final inset = uploaded == null ? 0.0 : size * .035;
                final portrait = Transform.scale(
                    scale: closePortrait ? 1.38 : 1,
                    alignment: Alignment.topCenter,
                    child: uploaded != null
                        ? Image.memory(uploaded,
                            gaplessPlayback: true,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _asset())
                        : _asset());
                return AvatarFrame(
                    size: size,
                    cornerRadius: cornerRadius,
                    color: Color(RoleAvatarStore.backgroundFor(role)),
                    child: uploaded == null
                        ? portrait
                        : Padding(
                            padding: EdgeInsets.all(inset),
                            child: ClipRSuperellipse(
                                borderRadius: BorderRadius.circular(
                                    ((cornerRadius ?? size * .24) - inset)
                                        .clamp(0.0, size)),
                                child: portrait)));
              }),
          if (showOnline)
            Positioned(
              right: 0,
              bottom: 1,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: BingoPalette.online,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white, width: onlineBorderWidth),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
