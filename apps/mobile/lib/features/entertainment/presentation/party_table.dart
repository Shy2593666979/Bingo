import 'dart:math' as math;
import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/presentation/entertainment_art.dart';
import 'package:bingo/features/entertainment/presentation/game_widgets.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

/// Shared seating for the invitation, preparation and conversation views.
/// Invitation portraits are candidates, never fabricated online/ready states.
class PartyTable extends StatelessWidget {
  const PartyTable(
      {required this.people,
      required this.username,
      this.userAvatarData,
      this.invitation = false,
      this.activeId,
      this.caption = '聊着玩一会儿',
      this.onInvite,
      super.key});
  final List<GameCompanion> people;
  final String username, caption;
  final String? userAvatarData, activeId;
  final bool invitation;
  final VoidCallback? onInvite;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final largeText = MediaQuery.textScalerOf(context).scale(12) > 17;
        final roster = people.take(6).toList();
        if (largeText) {
          return GameSurface(
              child: Column(children: [
            Text(caption, style: const TextStyle(fontSize: 18, color: gameInk)),
            const SizedBox(height: 18),
            GameRoster(
                people: roster,
                username: username,
                userAvatarData: userAvatarData),
            if (invitation)
              const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text('这些是可邀请的搭子',
                      style: TextStyle(fontSize: 12, color: gameMuted))),
          ]));
        }
        final width = box.maxWidth;
        final height = width * .91;
        final seatWidth = (width * .235).clamp(62.0, 85.0);
        final avatarSize = (width * .127).clamp(36.0, 48.0);
        // The user has a stable place; remaining seats visibly stay empty.
        final seats = <({GameCompanion? person, bool user})>[
          (person: null, user: true),
          ...roster.map((p) => (person: p, user: false)),
        ];
        final count = invitation ? 7 : seats.length;
        final spots = List.generate(count, (i) {
          final angle = math.pi / 2 + i * 2 * math.pi / count;
          return Offset(
              .5 + .37 * math.cos(angle), .48 + .36 * math.sin(angle));
        });
        return SizedBox(
            height: height,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                  left: width * .19,
                  right: width * .19,
                  top: height * .31,
                  height: height * .39,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(120),
                          border: Border.all(
                              color: const Color(0xFFF2D9E6), width: 1.5),
                          gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFFFF8FC), Color(0xFFF6E3ED)]),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFFC19AAE)
                                    .withValues(alpha: .10),
                                blurRadius: 20,
                                offset: const Offset(0, 12))
                          ]),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.auto_awesome_outlined,
                                size: 20, color: Color(0xFFD798B7)),
                            const SizedBox(height: 8),
                            Text(caption,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: gameInk)),
                            const SizedBox(height: 5),
                            Text(invitation ? '先选玩法，再邀请搭子' : '同一场小聚 · 一起参与',
                                style: const TextStyle(
                                    fontSize: 10, color: gameMuted)),
                          ]))),
              for (var i = 0; i < spots.length; i++)
                Positioned(
                    left: width * spots[i].dx - seatWidth / 2,
                    top: height * spots[i].dy - 43,
                    width: seatWidth,
                    child: i < seats.length
                        ? _seat(seats[i].person, seats[i].user, avatarSize)
                        : _empty(avatarSize)),
            ]));
      });
  Widget _seat(GameCompanion? person, bool user, double size) {
    final active = activeId == (user ? 'self' : person!.id);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                  color: active ? gameRose : const Color(0xFFF0E2E9),
                  width: active ? 2 : 1)),
          child: ClipOval(
              child: user
                  ? UserAvatar(
                      username: username,
                      avatarData: userAvatarData,
                      size: size)
                  : SizedBox.square(
                      dimension: size, child: EntertainmentPortrait(person!)))),
      const SizedBox(height: 5),
      Text(user ? '$username（你）' : person!.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11,
              color: active ? gameRose : gameInk,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      const SizedBox(height: 2),
      Text(
          active
              ? '示例发言'
              : user
                  ? '你的座位'
                  : invitation
                      ? '可邀请'
                      : '本局玩家',
          style: const TextStyle(fontSize: 9, color: gameMuted)),
    ]);
  }

  Widget _empty(double size) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(
            dimension: size + 10,
            child: OutlinedButton(
                onPressed: onInvite,
                style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                    side: const BorderSide(color: Color(0xFFE7D7E0))),
                child: const Icon(Icons.add_rounded,
                    size: 19, color: Color(0xFFC19AAD)))),
        const SizedBox(height: 5),
        const Text('留个位置', style: TextStyle(fontSize: 10, color: gameMuted)),
      ]);
}

class PartySeatStrip extends StatelessWidget {
  const PartySeatStrip(
      {required this.people,
      required this.username,
      this.userAvatarData,
      this.activeId,
      this.hostId,
      this.eliminatedIds = const {},
      this.nightMode = false,
      this.showSeatNumbers = false,
      super.key});
  final List<GameCompanion> people;
  final String username;
  final String? userAvatarData, activeId, hostId;
  final Set<String> eliminatedIds;
  final bool nightMode, showSeatNumbers;
  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final height = (112 + (textScale - 1) * 34).clamp(112.0, 168.0);
    final ink = nightMode ? const Color(0xFFF1EFF9) : gameInk;
    final muted = nightMode ? const Color(0xFF9EA5C0) : gameMuted;
    final border = nightMode ? const Color(0xFF282E46) : const Color(0xFFF1EDF0);
    final ringIdle =
        nightMode ? const Color(0xFF343C5A) : const Color(0xFFF0E2E9);
    final activeColor = nightMode ? const Color(0xFFA78BFA) : gameRose;
    return Container(
        height: height,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
        child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            scrollDirection: Axis.horizontal,
            itemCount: people.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final user = index == people.length;
              final person = user ? null : people[index];
              final id = user ? 'self' : person!.id;
              final host = !user && person!.id == hostId;
              final eliminated = eliminatedIds.contains(id);
              final active = !eliminated && activeId == id;
              final seatLabel = '${index + 1}号';
              return SizedBox(
                  width: 82,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                            height: 68,
                            child: Stack(
                                alignment: Alignment.topCenter,
                                clipBehavior: Clip.none,
                                children: [
                                  AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      padding: const EdgeInsets.all(2.5),
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: active
                                                  ? activeColor
                                                  : ringIdle,
                                              width: active ? 2.5 : 1.2),
                                          boxShadow: active
                                              ? [
                                                  BoxShadow(
                                                      color: activeColor
                                                          .withValues(
                                                              alpha: .32),
                                                      blurRadius: 10,
                                                      spreadRadius: 1)
                                                ]
                                              : null),
                                      child: Opacity(
                                          opacity: eliminated ? .35 : 1,
                                          child: ClipOval(
                                              child: user
                                                  ? UserAvatar(
                                                      username: username,
                                                      avatarData:
                                                          userAvatarData,
                                                      size: 54)
                                                  : GamePortrait(person!,
                                                      size: 54)))),
                                  if (showSeatNumbers)
                                    Positioned(
                                        top: -2,
                                        left: 4,
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                                color: eliminated
                                                    ? (nightMode
                                                        ? const Color(0xFF2B3046)
                                                        : const Color(0xFFDAD5D9))
                                                    : active
                                                        ? activeColor
                                                        : (nightMode
                                                            ? const Color(
                                                                0xFF2E3550)
                                                            : const Color(
                                                                0xFF3E3842)),
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: Text(seatLabel,
                                                style: const TextStyle(
                                                    fontSize: 9,
                                                    height: 1.2,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white)))),
                                  if (host)
                                    Positioned(
                                        bottom: 0,
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: gameRose,
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: const Text('主持人',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    height: 1.2,
                                                    color: Colors.white))))
                                  else if (active)
                                    Positioned(
                                        bottom: 0,
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: activeColor,
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: Text(
                                                nightMode ? '行动中' : '发言中',
                                                style: const TextStyle(
                                                    fontSize: 9,
                                                    height: 1.2,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white))))
                                  else if (eliminated)
                                    Positioned(
                                        bottom: 0,
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: nightMode
                                                    ? const Color(0xFF31374F)
                                                    : const Color(0xFF8E878D),
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: const Text('出局',
                                                style: TextStyle(
                                                    fontSize: 9,
                                                    height: 1.2,
                                                    color: Colors.white)))),
                                ])),
                        const SizedBox(height: 5),
                        Text(user ? '你' : person!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: eliminated
                                    ? muted
                                    : active
                                        ? activeColor
                                        : ink)),
                      ]));
            }));
  }
}
