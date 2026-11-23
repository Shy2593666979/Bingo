import 'package:bingo/core/design/approved_art.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:bingo/core/design/bingo_icon.dart';
import 'package:bingo/core/design/home_artwork_icon.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/theme/home_palette.dart';

const refMint = BingoPalette.primary;
const refInk = BingoPalette.ink;
const refMuted = BingoPalette.muted;

// Source files stay intact. Rectangles select illustration regions at render time;
// text, controls, lists and chat messages are native, interactive widgets.
class ReferenceArt extends StatelessWidget {
  const ReferenceArt(this.page, this.region,
      {this.width, this.height, super.key});
  final String page;
  final Rect region;
  final double? width, height;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: width,
      height: height,
      child: AspectRatio(
          aspectRatio: region.width / region.height,
          child: LayoutBuilder(builder: (_, constraints) {
            // v2 mockups are authored in a 705x1568 design space but shipped
            // at 841x1870; region rects stay in design space and are
            // normalized here. Older sources are 941x1672.
            const v2Sizes = <String, (double, double)>{
              'home2': (841.0, 1870.0),
              'create2': (841.0, 1870.0),
              'messages2': (841.0, 1870.0),
              'community2': (841.0, 1870.0),
              'profile2': (841.0, 1870.0),
            };
            final v2 = page.endsWith('2');
            var region = this.region;
            final (sourceWidth, sourceHeight) = v2
                ? (v2Sizes[page] ?? (705.0, 1568.0))
                : (
                    page == 'product_design' ? 1536.0 : 941.0,
                    page == 'product_design' ? 1024.0 : 1672.0
                  );
            if (v2) {
              final scaleW = sourceWidth / 705;
              final scaleH = sourceHeight / 1568;
              region = Rect.fromLTWH(region.left * scaleW, region.top * scaleH,
                  region.width * scaleW, region.height * scaleH);
            }
            final scale = math.max(constraints.maxWidth / region.width,
                constraints.maxHeight / region.height);
            return ClipRect(
                child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: sourceWidth * scale,
                    maxWidth: sourceWidth * scale,
                    minHeight: sourceHeight * scale,
                    maxHeight: sourceHeight * scale,
                    child: Transform.translate(
                        offset: Offset(
                            -region.left * scale +
                                (constraints.maxWidth - region.width * scale) /
                                    2,
                            -region.top * scale +
                                (constraints.maxHeight -
                                        region.height * scale) /
                                    2),
                        child: Image.asset('assets/reference/$page.webp',
                            width: sourceWidth * scale,
                            height: sourceHeight * scale,
                            fit: BoxFit.fill,
                            excludeFromSemantics: true))));
          })));
}

class ReferenceBackdrop extends StatelessWidget {
  const ReferenceBackdrop(
      {required this.child,
      this.chat = false,
      this.group = false,
      this.showHeaderArt = true,
      super.key});
  final Widget child;
  final bool chat;
  final bool group;
  final bool showHeaderArt;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Colors.white, child: child);
}

class ReferenceHeader extends StatelessWidget {
  const ReferenceHeader(this.title, this.subtitle,
      {this.actions = const [],
      this.back = false,
      this.padding = const EdgeInsets.fromLTRB(18, 15, 16, 15),
      super.key});
  final String title, subtitle;
  final List<Widget> actions;
  final bool back;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
      padding: padding,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (back)
          IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.chevron_left_rounded, size: 28)),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: refInk,
                  height: 1.3)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: refMuted))
          ],
        ])),
        ...actions,
      ]));
}

class ReferenceSurface extends StatelessWidget {
  const ReferenceSurface(
      {required this.child,
      this.padding = const EdgeInsets.all(14),
      super.key});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xFFFAFAFA),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: padding, child: child));
}

class ReferenceButton extends StatelessWidget {
  const ReferenceButton(this.label,
      {required this.onPressed,
      this.icon,
      this.small = false,
      this.outlined = false,
      super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool small, outlined;
  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          gradient: outlined ? null : BingoPalette.brandGradient,
          borderRadius: BorderRadius.circular(28)),
      child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
              foregroundColor: outlined ? refMint : Colors.white,
              minimumSize: Size(small ? 0 : 90, small ? 34 : 47),
              padding: EdgeInsets.symmetric(
                  horizontal: small ? 13 : 20, vertical: 8),
              side:
                  outlined ? const BorderSide(color: BingoPalette.blush) : null,
              shape: const StadiumBorder()),
          child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null && icon != Icons.arrow_forward_rounded) ...[
                  if (icon == Icons.chat_bubble_rounded ||
                      icon == Icons.forum_rounded ||
                      icon == Icons.forum_outlined ||
                      icon == Icons.chat_rounded)
                    BingoIcon(BingoSymbol.chat,
                        size: small ? 16 : 21,
                        selected: true,
                        color: outlined ? refMint : Colors.white)
                  else
                    Icon(icon, size: small ? 15 : 20),
                  const SizedBox(width: 6)
                ],
                Flexible(
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: small ? 12 : 15,
                            fontWeight: FontWeight.w700))),
                if (icon == Icons.arrow_forward_rounded) ...[
                  const SizedBox(width: 7),
                  Icon(icon, size: small ? 16 : 20)
                ],
              ])));
}

class ReferenceGroupCover extends StatelessWidget {
  const ReferenceGroupCover(this.cover, {this.size = 50, super.key});
  final String cover;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(size * .24),
      child: SizedBox.square(
          dimension: size,
          child: ReferenceArt(
              cover == 'garden' ? 'create_group' : 'home',
              cover == 'night'
                  ? const Rect.fromLTWH(500, 677, 105, 105)
                  : cover == 'garden'
                      ? const Rect.fromLTWH(64, 1073, 231, 168)
                      : const Rect.fromLTWH(60, 677, 105, 105))));
}

Rect? referenceAvatarRegion(String? role) => switch (role) {
      '女朋友' => const Rect.fromLTWH(53, 995, 125, 125),
      '男朋友' => const Rect.fromLTWH(53, 1147, 125, 125),
      '同事' || '朋友' => const Rect.fromLTWH(53, 1296, 125, 125),
      '老师' || '导师' => const Rect.fromLTWH(53, 1449, 125, 125),
      _ => null,
    };

class ReferenceNavigation extends StatelessWidget {
  const ReferenceNavigation(
      {required this.selected,
      required this.onSelected,
      required this.onCreate,
      this.creating = false,
      this.unread = 0,
      this.homeStyle = false,
      this.entertainment = false,
      super.key});
  final int selected, unread;
  final ValueChanged<int> onSelected;
  final VoidCallback onCreate;
  final bool creating;
  final bool homeStyle;
  final bool entertainment;
  @override
  Widget build(BuildContext context) {
    final page = entertainment
        ? selected
        : creating
            ? 2
            : switch (selected) { 0 => 0, 1 => 1, 2 => 3, _ => 4 };
    final extra = (MediaQuery.textScalerOf(context).scale(13) - 13) * 1.4;
    return Material(
        color: Colors.white,
        child: DecoratedBox(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: BingoPalette.line))),
            child: SafeArea(
                top: false,
                child: SizedBox(
                    height: (entertainment ? 68 : 64) + extra,
                    child: Row(children: [
                      for (var slot = 0; slot < 5; slot++)
                        Expanded(
                            child: Semantics(
                                label: slot == 2
                                    ? (entertainment ? '娱乐' : '创建中心')
                                    : null,
                                button: true,
                                selected: (entertainment || slot != 2) &&
                                    slot == page,
                                onTap: slot == 2
                                    ? (entertainment
                                        ? () => onSelected(2)
                                        : onCreate)
                                    : null,
                                excludeSemantics: slot == 2,
                                child: InkWell(
                                    onTap: () => entertainment
                                        ? onSelected(slot)
                                        : slot == 2
                                            ? onCreate()
                                            : onSelected(
                                                slot > 2 ? slot - 1 : slot),
                                    child: Padding(
                                        padding: EdgeInsets.only(
                                            top: homeStyle
                                                ? (slot == 2 ? 4 : 10)
                                                : 9),
                                        child: Column(children: [
                                          if (entertainment && slot == 2)
                                            SizedBox(
                                                height: 26,
                                                width: 26,
                                                child: Icon(
                                                    page == 2
                                                        ? Icons
                                                            .sports_esports_rounded
                                                        : Icons
                                                            .sports_esports_outlined,
                                                    size: 26,
                                                    color: page == 2
                                                        ? BingoPalette.primary
                                                        : const Color(
                                                            0xFF909090)))
                                          else if (homeStyle)
                                            HomeArtworkIcon(
                                              const [
                                                HomeArtwork.home,
                                                HomeArtwork.chatTab,
                                                HomeArtwork.create,
                                                HomeArtwork.compass,
                                                HomeArtwork.profile
                                              ][slot],
                                              size: slot == 2 ? 32 : 22,
                                              color: slot == 0 || slot == 2
                                                  ? HomePalette.accent
                                                  : HomePalette.navMuted,
                                            )
                                          else
                                            Transform.scale(
                                                scale: entertainment ? 1.08 : 1,
                                                child: ApprovedNavIcon(
                                                    page: page, item: slot)),
                                          if (entertainment ||
                                              slot != 2 ||
                                              homeStyle) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                                [
                                                  '首页',
                                                  '聊天',
                                                  if (entertainment)
                                                    '娱乐'
                                                  else if (homeStyle)
                                                    '创建'
                                                  else
                                                    '',
                                                  '社区',
                                                  '我的'
                                                ][slot],
                                                style: TextStyle(
                                                    fontSize:
                                                        entertainment ? 14 : 13,
                                                    height: 1.4,
                                                    fontWeight: slot == page
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                    color: slot == page
                                                        ? (entertainment
                                                            ? BingoPalette
                                                                .primary
                                                            : homeStyle
                                                                ? HomePalette
                                                                    .accent
                                                                : BingoPalette
                                                                    .ink)
                                                        : Color(homeStyle
                                                            ? 0xFF989294
                                                            : 0xFF909090)))
                                          ],
                                        ])))))
                    ])))));
  }
}
