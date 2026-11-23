import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:flutter/material.dart';

/// The original transparent project portraits, without a square avatar frame.
/// Uploaded portraits stay attached to the actual role, never to a fixed name.
class EntertainmentPortrait extends StatelessWidget {
  const EntertainmentPortrait(this.person, {super.key});
  final GameCompanion person;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: RoleAvatarStore.images,
      builder: (context, _) {
        final bytes = RoleAvatarStore.images.value[person.avatarKey];
        final asset = squareAvatarAsset(
            RoleAvatarStore.assets[person.avatarKey] ??
                assistantAvatarAsset(person.avatarKey));
        final fallback = Image.asset(asset,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            cacheWidth: 600);
        return bytes == null
            ? fallback
            : ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(bytes,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    errorBuilder: (_, __, ___) => fallback));
      });
}
