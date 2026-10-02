import 'package:flutter/material.dart';
import 'package:bingo/core/role_avatar_store.dart';

String assistantAvatarAsset(String? role) => switch (role) {
      '男朋友' => 'assets/images/boyfriend.png',
      '女朋友' => 'assets/images/girlfriend.png',
      '家长' => 'assets/images/parent.png',
      '老师' || '导师' => 'assets/images/teacher.png',
      '小朋友' || '小孩' || '儿子' || '女儿' => 'assets/images/child.png',
      '同事' || '朋友' => 'assets/images/colleague.png',
      _ => 'assets/images/bingo_logo.png',
    };

class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({
    required this.role,
    required this.size,
    this.showOnline = false,
    super.key,
  });

  final String? role;
  final double size;
  final bool showOnline;

  @override
  Widget build(BuildContext context) {
    final dotSize = size * 0.27;
    return SizedBox.square(
      dimension: size + (showOnline ? dotSize * 0.18 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: ClipOval(
              child: ValueListenableBuilder(
                valueListenable: RoleAvatarStore.images,
                builder: (context, images, _) => images[role] != null
                    ? Image.memory(images[role]!, fit: BoxFit.cover)
                    : Transform.scale(
                        scale: 1.12,
                        child: Image.asset(
                          assistantAvatarAsset(role),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                            'assets/images/bingo_logo.png',
                            fit: BoxFit.cover,
                          ),
                        )),
              ),
            ),
          ),
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
