import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/presentation/entertainment_art.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

const gameInk = Color(0xFF29262A);
const gameMuted = Color(0xFF857D83);
const gameLine = Color(0xFFEDE7EB);
const gameRose = Color(0xFFED5688);
const gameLilac = Color(0xFFA382C1);

class GameAccent extends StatelessWidget {
  const GameAccent({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 22, height: 26, child: CustomPaint(painter: _AccentPainter()));
}

class _AccentPainter extends CustomPainter {
  const _AccentPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gameRose
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(3, 9), const Offset(5, 2), paint);
    canvas.drawLine(const Offset(8, 14), const Offset(17, 7), paint);
    canvas.drawLine(const Offset(12, 22), const Offset(20, 21), paint);
  }

  @override
  bool shouldRepaint(covariant _AccentPainter oldDelegate) => false;
}

class GameSurface extends StatelessWidget {
  const GameSurface(
      {required this.child,
      this.lilac = false,
      this.padding = const EdgeInsets.all(18),
      super.key});
  final Widget child;
  final bool lilac;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: lilac
                  ? const [Color(0xFFF5EDFC), Color(0xFFFFFAFD)]
                  : const [Color(0xFFFFF0F7), Color(0xFFFFFBFD)]),
          border: Border.all(color: lilac ? const Color(0xFFE6D5F0) : gameLine),
          borderRadius: BorderRadius.circular(22)),
      child: child);
}

class GameButton extends StatelessWidget {
  const GameButton(this.label,
      {required this.onPressed, this.outlined = false, super.key});
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
              backgroundColor: outlined ? Colors.white : gameRose,
              foregroundColor: outlined ? gameRose : Colors.white,
              minimumSize: const Size(0, 52),
              side: outlined ? const BorderSide(color: gameLine) : null,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
          child: Text(label,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))));
}

class GamePortrait extends StatelessWidget {
  const GamePortrait(this.person, {this.size = 54, super.key});
  final GameCompanion person;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .22),
          child: ColoredBox(
              color: const Color(0xFFFAF2F6),
              child: EntertainmentPortrait(person))));
}

class GameRoster extends StatelessWidget {
  const GameRoster(
      {required this.people,
      required this.username,
      this.userAvatarData,
      super.key});
  final List<GameCompanion> people;
  final String username;
  final String? userAvatarData;
  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 12, runSpacing: 16, children: [
        _item(
            UserAvatar(
                username: username, avatarData: userAvatarData, size: 51),
            '$username（你）'),
        ...people.map((p) => _item(GamePortrait(p, size: 51), p.name))
      ]);
  Widget _item(Widget avatar, String label) => SizedBox(
      width: 68,
      child: Column(children: [
        avatar,
        const SizedBox(height: 8),
        Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.4, color: gameInk))
      ]));
}

class GameSectionTitle extends StatelessWidget {
  const GameSectionTitle(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 23,
                height: 1.4,
                color: gameInk,
                fontWeight: FontWeight.w600)),
        if (subtitle != null) ...[
          const SizedBox(height: 7),
          Text(subtitle!,
              style:
                  const TextStyle(fontSize: 13, height: 1.8, color: gameMuted))
        ]
      ]));
}
