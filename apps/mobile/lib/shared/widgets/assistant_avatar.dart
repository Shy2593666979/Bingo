import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:flutter/material.dart';
import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/core/role_avatar_assets.dart';

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
      _ => 'assets/images/bingo_logo.png',
    };

class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({
    required this.role,
    required this.size,
    this.showOnline = false,
    this.cornerRadius,
    super.key,
  });

  final String? role;
  final double size;
  final bool showOnline;
  final double? cornerRadius;

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
    final dotSize = size * 0.27;
    return SizedBox.square(
      dimension: size + (showOnline ? dotSize * 0.18 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ValueListenableBuilder(
              valueListenable: RoleAvatarStore.images,
              builder: (context, images, _) => AvatarFrame(
                  size: size,
                  cornerRadius: cornerRadius,
                  color: isTransparentRoleAvatarAsset(
                          RoleAvatarStore.assets[role] ??
                              assistantAvatarAsset(role))
                      ? Colors.transparent
                      : const Color(0xFFE8F8F2),
                  child: images[role] != null
                      ? Image.memory(images[role]!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _asset())
                      : _asset())),
          if (showOnline)
            Positioned(
              right: 0,
              bottom: 1,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF20B477),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
