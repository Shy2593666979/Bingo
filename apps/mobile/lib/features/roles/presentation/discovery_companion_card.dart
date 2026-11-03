import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_widgets.dart';
import 'package:bingo/features/roles/role_traits.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

/// One image layout for every recommendation, including non-human uploads.
class DiscoveryCompanionCard extends StatelessWidget {
  const DiscoveryCompanionCard({
    required this.share,
    required this.gateway,
    required this.onDetail,
    required this.onAdd,
    this.adding = false,
    super.key,
  });

  final CommunityShare share;
  final CommunityGateway gateway;
  final VoidCallback onDetail;
  final VoidCallback? onAdd;
  final bool adding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1253CE9E), blurRadius: 25, offset: Offset(0, 10))
          ]),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: CustomPaint(
              painter: const _RecommendationWaves(),
              child: Container(
                  constraints: const BoxConstraints(minHeight: 196),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(27)),
                  padding: const EdgeInsets.fromLTRB(17, 17, 17, 13),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final imageSize = constraints.maxWidth < 270 ? 80.0 : 96.0;
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: InkWell(
                                        onTap: onDetail,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(share.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 23,
                                                      height: 1.3,
                                                      letterSpacing: -.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color:
                                                          Color(0xFF0D3624))),
                                              if (share.roleType?.isNotEmpty ==
                                                  true)
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 3),
                                                    child: Text(
                                                        share.roleType!,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color: Color(
                                                                0xFF71877C)))),
                                              if (share.traits.isNotEmpty)
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 9),
                                                    child: Wrap(
                                                        spacing: 5,
                                                        runSpacing: 4,
                                                        children: [
                                                          for (final tag
                                                              in share.traits
                                                                  .take(2))
                                                            _trait(tag)
                                                        ])),
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 8),
                                                  child: Text(
                                                      share.introduction,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          height: 1.65,
                                                          color: Color(
                                                              0xFF63816D)))),
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Row(children: [
                                                    UserAvatar(
                                                        username:
                                                            share.authorName,
                                                        size: 13),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                        child: Text(
                                                            '${share.authorName}分享',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: const TextStyle(
                                                                fontSize: 9,
                                                                color: Color(
                                                                    0xFF86A68E))))
                                                  ])),
                                            ]))),
                                const SizedBox(width: 13),
                                Semantics(
                                    label: '查看${share.name}的搭子详情',
                                    button: true,
                                    child: InkWell(
                                        onTap: onDetail,
                                        borderRadius: BorderRadius.circular(22),
                                        child: Container(
                                            width: imageSize,
                                            height: imageSize,
                                            decoration: BoxDecoration(
                                                color: const Color(0xFFE0F3E8),
                                                borderRadius:
                                                    BorderRadius.circular(22),
                                                border: Border.all(
                                                    color: Colors.white)),
                                            clipBehavior: Clip.antiAlias,
                                            child: CompanionPortrait(
                                                share: share,
                                                gateway: gateway,
                                                fit: BoxFit.contain)))),
                              ]),
                          const SizedBox(height: 13),
                          DecoratedBox(
                              decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFF59D7AD),
                                    Color(0xFF06A873),
                                    Color(0xFF009E6C)
                                  ]),
                                  borderRadius: BorderRadius.circular(22)),
                              child: TextButton.icon(
                                  key: ValueKey('recommend-add-${share.id}'),
                                  onPressed: onAdd,
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      disabledForegroundColor: Colors.white70,
                                      minimumSize: const Size(0, 33),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      textStyle: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                  icon: const Icon(Icons.add, size: 15),
                                  label: Text(adding ? '添加中' : '添加搭子'))),
                        ]);
                  })))));

  Widget _trait(String tag) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        TraitIcon(roleTraits[tag] ?? 'chat',
            size: 11, color: const Color(0xFF36B758)),
        const SizedBox(width: 3),
        Flexible(
            child: Text(tag,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: Color(0xFF28753D))))
      ]));
}

class _RecommendationWaves extends CustomPainter {
  const _RecommendationWaves();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF5FCF8), Color(0xFFEAF8EF)])
              .createShader(Offset.zero & size));
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height * .59)
          ..quadraticBezierTo(size.width * .57, size.height * .17, size.width,
              size.height * .27)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = const Color(0xFFD9F5E4));
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height * .88)
          ..quadraticBezierTo(size.width * .42, size.height * .67, size.width,
              size.height * .88)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RecommendationWaves oldDelegate) => false;
}
