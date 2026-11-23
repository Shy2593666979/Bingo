import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/presentation/entertainment_art.dart';
import 'package:bingo/features/entertainment/presentation/game_widgets.dart';
import 'package:flutter/material.dart';

class EntertainmentHome extends StatelessWidget {
  const EntertainmentHome(
      {required this.people,
      required this.loading,
      required this.failed,
      required this.onRefresh,
      required this.onCreate,
      required this.onCreateRole,
      required this.onStart,
      this.username = '我',
      this.userAvatarData,
      this.resumeTitle,
      this.resumeSubtitle = '回到上次的小聚',
      this.onResume,
      super.key});
  final List<GameCompanion> people;
  final bool loading, failed;
  final String username;
  final String? userAvatarData, resumeTitle;
  final String resumeSubtitle;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate, onCreateRole;
  final ValueChanged<CompanionGame> onStart;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.white,
      child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 18),
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Row(children: [
                        Flexible(
                            child: Text('一起坐坐',
                                style: TextStyle(
                                    fontSize: 34,
                                    height: 1.25,
                                    color: gameInk,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -.5))),
                        SizedBox(width: 8),
                        SizedBox(
                            width: 19,
                            height: 24,
                            child: CustomPaint(painter: _TitleAccentPainter())),
                      ])),
                      IconButton(
                          constraints: const BoxConstraints.tightFor(
                              width: 104, height: 40),
                          padding: EdgeInsets.zero,
                          onPressed: onCreate,
                          tooltip: '创建搭子或群聊',
                          icon: Transform.translate(
                              offset: const Offset(0, 20),
                              child: OverflowBox(
                                  minWidth: 60,
                                  maxWidth: 60,
                                  minHeight: 60,
                                  maxHeight: 60,
                                  child: Image.asset(
                                      'assets/entertainment/party-confetti.webp',
                                      width: 60,
                                      height: 60)))),
                    ]),
                    const SizedBox(height: 4),
                    const Text('和熟悉的搭子，玩点不一样的',
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Color(0xFF625C61))),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                            width: 103,
                            height: 2,
                            margin: const EdgeInsets.only(top: 6, bottom: 20),
                            decoration: BoxDecoration(
                                color: const Color(0xFFF39AB8),
                                borderRadius: BorderRadius.circular(8)))),
                    if (loading) const LinearProgressIndicator(minHeight: 2),
                    if (failed)
                      Row(children: [
                        const Expanded(
                            child: Text('搭子暂时没读到，稍后重试。',
                                style:
                                    TextStyle(fontSize: 12, color: gameMuted))),
                        TextButton(
                            onPressed: onRefresh, child: const Text('重试'))
                      ]),
                    for (final game in CompanionGame.values) ...[
                      _Activity(
                          game: game,
                          onTap: loading ? null : () => onStart(game)),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 4),
                    Row(children: [
                      const Expanded(
                          child: Text('我的搭子',
                              style: TextStyle(
                                  fontSize: 19,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                  color: gameInk))),
                      TextButton(
                          onPressed: () => onStart(CompanionGame.truth),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: const Size(70, 32)),
                          child: const Text('全部搭子 ›',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF94697E)))),
                    ]),
                    const SizedBox(height: 12),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final person in people.take(4))
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.only(right: 9),
                                    child: InkWell(
                                        onTap: loading
                                            ? null
                                            : () =>
                                                onStart(CompanionGame.truth),
                                        borderRadius: BorderRadius.circular(14),
                                        child: Column(children: [
                                          Container(
                                              width: 68,
                                              height: 68,
                                              clipBehavior: Clip.antiAlias,
                                              decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFFAF2F6),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          15)),
                                              child: EntertainmentPortrait(
                                                  person)),
                                          const SizedBox(height: 6),
                                          Text(person.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  height: 1.4,
                                                  color: gameInk)),
                                        ])))),
                          if (people.isNotEmpty)
                            SizedBox(
                                width: 26,
                                height: 64,
                                child: Center(
                                    child: InkWell(
                                        onTap: () =>
                                            onStart(CompanionGame.truth),
                                        child: const CircleAvatar(
                                            radius: 14,
                                            backgroundColor: Color(0xFFFAF2F6),
                                            child: Icon(Icons.more_horiz,
                                                size: 17, color: gameMuted))))),
                        ]),
                    if (!loading && people.isEmpty)
                      TextButton(
                          onPressed: onCreateRole,
                          child: const Text('先创建两位搭子，一起开场')),
                    if (resumeTitle != null) ...[
                      const SizedBox(height: 20),
                      const Text('继续游戏',
                          style: TextStyle(
                              fontSize: 19,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: gameInk)),
                      const SizedBox(height: 8),
                      Material(
                          color: const Color(0xFFFCF2F6),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                              onTap: onResume,
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 13, vertical: 9),
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                          color: const Color(0xFFF1E4EB))),
                                  child: Row(children: [
                                    Image.asset(
                                        'assets/entertainment/resume-cards.webp',
                                        width: 44,
                                        height: 44),
                                    const SizedBox(width: 11),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(resumeTitle!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: gameInk)),
                                          const SizedBox(height: 3),
                                          Text(resumeSubtitle,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: gameMuted)),
                                        ])),
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 15, vertical: 6),
                                        decoration: BoxDecoration(
                                            color: gameRose,
                                            borderRadius:
                                                BorderRadius.circular(18)),
                                        child: const Text('继续 ›',
                                            style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.white))),
                                  ])))),
                    ],
                  ]))));
}

class _TitleAccentPainter extends CustomPainter {
  const _TitleAccentPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gameRose
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(2, 9), const Offset(4, 2), paint);
    canvas.drawLine(const Offset(8, 13), const Offset(16, 7), paint);
    canvas.drawLine(const Offset(11, 20), const Offset(19, 19), paint);
  }

  @override
  bool shouldRepaint(covariant _TitleAccentPainter oldDelegate) => false;
}

class _Activity extends StatelessWidget {
  const _Activity({required this.game, required this.onTap});
  final CompanionGame game;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final truth = game == CompanionGame.truth;
    final scaled = MediaQuery.textScalerOf(context).scale(15) / 15;
    return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: SizedBox(
                height: 143 + (scaled - 1) * 210,
                child: Stack(children: [
                  Positioned.fill(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: truth
                                      ? const [
                                          Color(0xFFFFF0F7),
                                          Color(0xFFFCE1EE)
                                        ]
                                      : const [
                                          Color(0xFFFFF0E3),
                                          Color(0xFFFFF0E8)
                                        ])))),
                  Positioned(
                      right: 0,
                      bottom: 5,
                      width: 139,
                      height: 136,
                      child: ExcludeSemantics(
                          child: ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (rect) => const LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Colors.white,
                                        Colors.white
                                      ],
                                      stops: [
                                        0,
                                        .13,
                                        1
                                      ]).createShader(rect),
                              child: Image.asset(
                                  truth
                                      ? 'assets/entertainment/truth-card-art.webp'
                                      : 'assets/entertainment/wolf-card-art.webp',
                                  fit: BoxFit.fill)))),
                  Positioned.fill(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 17, 12, 12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(game.title,
                                    style: const TextStyle(
                                        fontSize: 24,
                                        height: 1.3,
                                        fontWeight: FontWeight.w700,
                                        color: gameInk,
                                        letterSpacing: -.6)),
                                const SizedBox(height: 6),
                                Padding(
                                    padding: EdgeInsets.only(
                                        right: scaled > 1.3 ? 0 : 92),
                                    child: Text(
                                        truth
                                            ? '聊真心，做挑战，更了解彼此'
                                            : '推理发言，找出隐藏的狼人',
                                        style: const TextStyle(
                                            fontSize: 14,
                                            height: 1.5,
                                            color: Color(0xFF645A61)))),
                                const Spacer(),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 8),
                                    decoration: BoxDecoration(
                                        color: gameRose,
                                        borderRadius:
                                            BorderRadius.circular(22)),
                                    child: Text(truth ? '去玩一玩 ›' : '去组局 ›',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                            color: Colors.white))),
                              ]))),
                ]))));
  }
}
