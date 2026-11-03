import 'package:bingo/core/role_avatar_assets.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:flutter/material.dart';
import 'package:bingo/core/theme/app_theme.dart';

const communityInk = BingoPalette.ink;
const communityMuted = BingoPalette.muted;
const communityAccent = BingoPalette.primary;
const communityBackground = BingoPalette.ice;

class SharedCompanionAvatar extends StatelessWidget {
  const SharedCompanionAvatar(
      {required this.share, required this.gateway, this.size = 72, super.key});
  final CommunityShare share;
  final CommunityGateway gateway;
  final double size;
  @override
  Widget build(BuildContext context) {
    const allowed = roleAvatarFiles;
    final fallback = Image.asset(
        squareAvatarAsset(
            'assets/images/${allowed.contains(share.avatarAsset) ? share.avatarAsset : 'bingo_logo.png'}'),
        fit: BoxFit.cover);
    return AvatarFrame(
        size: size,
        child: SizedBox.square(
            dimension: size,
            child: ColoredBox(
                color: BingoPalette.softSurface,
                child: share.hasAvatar
                    ? Image.network(gateway.communityAvatarUrl(share.id),
                        fit: BoxFit.cover,
                        cacheWidth:
                            (size * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        headers: {
                          if (gateway.communityAccessToken != null)
                            'Authorization':
                                'Bearer ${gateway.communityAccessToken}'
                        },
                        errorBuilder: (_, error, stack) => fallback)
                    : fallback)));
  }
}

class CompanionPortrait extends StatelessWidget {
  const CompanionPortrait(
      {required this.share,
      required this.gateway,
      this.fit = BoxFit.cover,
      super.key});
  final CommunityShare share;
  final CommunityGateway gateway;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    const allowed = roleAvatarFiles;
    final fallback = ColoredBox(
        color: BingoPalette.softSurface,
        child: Image.asset(
            squareAvatarAsset(
                'assets/images/${allowed.contains(share.avatarAsset) ? share.avatarAsset : 'bingo_logo.png'}'),
            fit: fit));
    return share.hasAvatar
        ? Image.network(gateway.communityAvatarUrl(share.id),
            fit: fit,
            headers: {
              if (gateway.communityAccessToken != null)
                'Authorization': 'Bearer ${gateway.communityAccessToken}'
            },
            errorBuilder: (_, __, ___) => fallback)
        : fallback;
  }
}

class SharedPostImage extends StatelessWidget {
  const SharedPostImage(
      {required this.share,
      required this.gateway,
      required this.index,
      required this.fallback,
      super.key});
  final CommunityShare share;
  final CommunityGateway gateway;
  final int index;
  final Widget fallback;
  @override
  Widget build(BuildContext context) =>
      Image.network(gateway.communityImageUrl(share.id, index),
          fit: BoxFit.cover,
          cacheWidth: 600,
          headers: {
            if (gateway.communityAccessToken != null)
              'Authorization': 'Bearer ${gateway.communityAccessToken}'
          },
          errorBuilder: (_, error, stack) => fallback);
}

class CommunityTags extends StatelessWidget {
  const CommunityTags(this.tags, {super.key});
  final List<String> tags;
  @override
  Widget build(BuildContext context) => Wrap(
      spacing: 5,
      runSpacing: 6,
      children: tags
          .map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: BingoPalette.softSurface,
                  borderRadius: BorderRadius.circular(7)),
              child: Text(tag,
                  style: const TextStyle(
                      fontSize: 10, color: BingoPalette.primary))))
          .toList());
}

class CommunityEmpty extends StatelessWidget {
  const CommunityEmpty(
      {required this.title,
      required this.description,
      this.onAction,
      this.action = '分享我的搭子',
      super.key});
  final String title, description, action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 35),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                color: Color(0xFFE8F2EC), shape: BoxShape.circle),
            child: const Icon(Icons.diversity_1_outlined,
                size: 36, color: Color(0xFF8CAB99))),
        const SizedBox(height: 17),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: communityInk)),
        const SizedBox(height: 8),
        Text(description,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, height: 1.7, color: communityMuted)),
        if (onAction != null) ...[
          const SizedBox(height: 20),
          FilledButton(onPressed: onAction, child: Text(action))
        ],
      ]));
}
