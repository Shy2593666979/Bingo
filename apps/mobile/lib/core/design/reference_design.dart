import 'dart:math' as math;
import 'package:bingo/core/design/companion_launch_ui.dart';
import 'package:flutter/material.dart';
import 'package:bingo/core/design/bingo_icon.dart';
import 'package:bingo/core/theme/app_theme.dart';

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
  Widget build(BuildContext context) => DecoratedBox(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
            BingoPalette.pageTop,
            BingoPalette.ice,
            BingoPalette.pageBottom
          ])),
      child: Stack(children: [
        if (showHeaderArt)
          Positioned(
              top: MediaQuery.paddingOf(context).top + 2,
              right: 0,
              width: chat ? 106 : 180,
              height: chat ? 63 : 59,
              child: IgnorePointer(
                  child: Opacity(
                      opacity: .9,
                      child: _softArt(
                          chat ? 'group_chat' : 'home',
                          chat
                              ? const Rect.fromLTWH(650, 60, 190, 112)
                              : const Rect.fromLTWH(515, 60, 426, 138))))),
        if (chat && group)
          Positioned(
              top: MediaQuery.sizeOf(context).height * .24,
              right: 3,
              width: 78,
              height: 60,
              child: IgnorePointer(
                  child: _softArt(
                      'group_chat', const Rect.fromLTWH(725, 403, 195, 150)))),
        if (chat)
          Positioned(
              top: MediaQuery.sizeOf(context).height * .36,
              right: 2,
              width: 93,
              height: group ? 96 : 85,
              child: IgnorePointer(
                  child: Opacity(
                      opacity: .88,
                      child: _softArt(
                          group ? 'group_chat' : 'single_chat',
                          group
                              ? const Rect.fromLTWH(721, 657, 210, 217)
                              : const Rect.fromLTWH(685, 800, 240, 220))))),
        if (chat)
          Positioned(
              bottom: 0,
              right: 0,
              width: 88,
              height: 175,
              child: IgnorePointer(
                  child: Opacity(
                      opacity: .55,
                      child: _softArt('group_chat',
                          const Rect.fromLTWH(800, 1280, 141, 280))))),
        Positioned.fill(child: child),
      ]));

  Widget _softArt(String page, Rect region) => ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent
          ], stops: [
            0,
            .08,
            .92,
            1
          ]).createShader(bounds),
      child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent
                  ],
                  stops: [
                    0,
                    .08,
                    .92,
                    1
                  ]).createShader(bounds),
          child: ReferenceArt(page, region)));
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
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
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
      color: BingoPalette.surface.withValues(alpha: .96),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: .9))),
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
                  outlined ? const BorderSide(color: Color(0xFFB7EEE0)) : null,
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
      super.key});
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onCreate;
  final bool creating;
  final int unread;
  @override
  Widget build(BuildContext context) {
    final compact = CompanionLaunch.compact(context);
    final labelSize = compact ? 13.0 : 15.0;
    final extraLabelHeight =
        (MediaQuery.textScalerOf(context).scale(labelSize) - labelSize) * 1.25;
    return DecoratedBox(
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: CompanionLaunch.line))),
        child: SafeArea(
            top: false,
            child: SizedBox(
                height: (compact ? 73 : 78) + extraLabelHeight,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(15, 6, 15, 6),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _item(0, '首页', BingoSymbol.home, labelSize),
                          _item(1, '聊天', BingoSymbol.chat, labelSize),
                          Expanded(
                              child: Semantics(
                                  label: '创建中心',
                                  button: true,
                                  excludeSemantics: true,
                                  child: InkWell(
                                      onTap: onCreate,
                                      child: SizedBox(
                                          height: 61,
                                          child: Align(
                                              alignment: Alignment(0, -.6),
                                              child: Container(
                                                  width: 41,
                                                  height: 41,
                                                  decoration:
                                                      const BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          gradient:
                                                              LinearGradient(
                                                                  colors: [
                                                                Color(
                                                                    0xFF12C59E),
                                                                CompanionLaunch
                                                                    .primary,
                                                              ])),
                                                  child: const Icon(
                                                      Icons.add_rounded,
                                                      color: Colors.white,
                                                      size: 26))))))),
                          _item(2, '社区', BingoSymbol.partners, labelSize),
                          _item(3, '我的', BingoSymbol.profile, labelSize),
                        ])))));
  }

  Widget _item(int index, String title, BingoSymbol symbol, double labelSize) {
    final active = selected == index && !creating;
    final color = active ? CompanionLaunch.primary : const Color(0xFF334D3D);
    return Expanded(
        child: Semantics(
            button: true,
            selected: active,
            child: InkWell(
                onTap: () => onSelected(index),
                child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Column(children: [
                      Badge(
                          isLabelVisible: index == 1 && unread > 0,
                          backgroundColor: const Color(0xFFFF4D4F),
                          label: Text(unread > 99 ? '99+' : '$unread'),
                          child: index == 3
                              ? Icon(
                                  active
                                      ? Icons.person_rounded
                                      : Icons.person_outline_rounded,
                                  color: color,
                                  size: 27)
                              : BingoIcon(symbol,
                                  color: color,
                                  size: 27,
                                  selected: index == 0 && active)),
                      const SizedBox(height: 6),
                      Text(title,
                          style: CompanionLaunch.text(labelSize,
                              color: color, height: 1.25)),
                    ])))));
  }
}
