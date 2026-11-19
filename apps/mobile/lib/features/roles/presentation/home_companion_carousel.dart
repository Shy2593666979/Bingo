import 'dart:async';
import 'dart:math' as math;

import 'package:bingo/core/design/home_artwork_icon.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/roles/presentation/home_postcard_background.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';

class HomeCompanionCarousel extends StatefulWidget {
  const HomeCompanionCarousel({
    required this.roles,
    required this.active,
    required this.onChat,
    required this.onDetail,
    required this.onAll,
    super.key,
  });

  final List<RoleOption> roles;
  final bool active;
  final Future<void> Function(RoleOption) onChat, onDetail;
  final VoidCallback onAll;

  @override
  State<HomeCompanionCarousel> createState() => _HomeCompanionCarouselState();
}

class _HomeCompanionCarouselState extends State<HomeCompanionCarousel>
    with WidgetsBindingObserver {
  late final _pages = PageController(
      initialPage: widget.roles.length == 1 ? 0 : widget.roles.length * 1024);
  late int _page = _pages.initialPage;
  final _strip = ScrollController();
  Timer? _timer;
  bool _opening = false, _touching = false;
  bool _foreground = true;
  bool get _multiple => widget.roles.length > 1;
  int get _index => _page % widget.roles.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _schedule();
  }

  @override
  void didUpdateWidget(covariant HomeCompanionCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_multiple || !widget.active || !_foreground) return;
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          !_touching &&
          !_opening &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          !MediaQuery.disableAnimationsOf(context) &&
          _pages.hasClients &&
          !_pages.position.isScrollingNotifier.value) {
        _move(_page + 1);
      } else {
        _schedule();
      }
    });
  }

  void _move(int page) {
    if (!_multiple || !_pages.hasClients || page < 0 || page == _page) return;
    _schedule();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      unawaited(_pages.animateToPage(page,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic));
    }
  }

  Future<void> _open(
      Future<void> Function(RoleOption) action, RoleOption role) async {
    if (_opening) return;
    _opening = true;
    try {
      await action(role);
    } finally {
      _opening = false;
      if (mounted) _schedule();
    }
  }

  void _pageChanged(int page) {
    setState(() => _page = page);
    if (!_strip.hasClients) return;
    final position = _strip.position;
    final cell = position.viewportDimension / 5;
    final first = position.pixels;
    final left = _index * cell;
    final right = left + cell;
    final target = left < first
        ? left
        : right > first + position.viewportDimension
            ? right - position.viewportDimension
            : first;
    if (target != first) {
      final offset = target.clamp(0.0, position.maxScrollExtent);
      if (MediaQuery.disableAnimationsOf(context)) {
        _strip.jumpTo(offset);
      } else {
        unawaited(_strip.animateTo(offset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pages.dispose();
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final height =
        (MediaQuery.sizeOf(context).width - 28).clamp(260.0, 440.0) * .54 +
            math.max(0, scale.scale(21) - 21) * 2.4 +
            math.max(0, scale.scale(14) - 14) * 4;
    final controlStyle = TextButton.styleFrom(
      minimumSize: const Size(42, 35),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: BingoPalette.muted,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Listener(
        onPointerDown: (_) => _touching = true,
        onPointerUp: (_) {
          _touching = false;
          _schedule();
        },
        onPointerCancel: (_) {
          _touching = false;
          _schedule();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x20C4517E),
                  blurRadius: 16,
                  offset: Offset(0, 6)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: SizedBox(
              height: height,
              child: Stack(alignment: Alignment.center, children: [
                const Positioned.fill(
                    child: CustomPaint(painter: HomePostcardBackground())),
                PageView.builder(
                  controller: _pages,
                  physics: _multiple
                      ? const PageScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: _multiple ? null : 1,
                  onPageChanged: _pageChanged,
                  itemBuilder: (context, page) =>
                      _card(widget.roles[page % widget.roles.length]),
                ),
                if (_multiple) ...[
                  Positioned(left: -10, child: _arrow(-1, '上一位搭子')),
                  Positioned(right: -10, child: _arrow(1, '下一位搭子')),
                ],
                Positioned.fill(
                    child: IgnorePointer(
                        child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(color: const Color(0xFFF7BDD3)),
                  ),
                ))),
              ]),
            ),
          ),
        ),
      ),
      if (_multiple)
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < math.min(widget.roles.length, 5); i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index % 5
                        ? const Color(0xFFE84579)
                        : const Color(0xFFF9D5E2),
                  ),
                ),
            ]),
          ),
        ),
      const SizedBox(height: 9),
      Row(children: [
        Expanded(
          child: Text('今天想和谁聊聊？',
              style: BingoTypography.sectionTitle.copyWith(fontSize: 17)),
        ),
        TextButton(
            style: controlStyle,
            onPressed: widget.onAll,
            child: const Text('全部 ›', style: TextStyle(fontSize: 12))),
      ]),
      SizedBox(
        key: const ValueKey('companion-preview'),
        height: 55 + scale.scale(12) * 1.4,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView.builder(
            controller: _strip,
            scrollDirection: Axis.horizontal,
            itemExtent: constraints.maxWidth / 5,
            itemCount: widget.roles.length,
            itemBuilder: (context, index) {
              final role = widget.roles[index];
              final selected = index == _index;
              final size = (constraints.maxWidth / 5 - 11).clamp(32.0, 44.0);
              return Semantics(
                selected: selected,
                button: true,
                child: InkWell(
                  key: ValueKey('companion-card-${role.id}'),
                  onTap: () => _move(_page + index - _index),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? BingoPalette.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: AssistantAvatar(
                          role: role.name, size: size, closePortrait: true),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(role.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BingoTypography.caption.copyWith(
                              color: selected
                                  ? BingoPalette.primary
                                  : BingoPalette.ink,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }

  Widget _arrow(int direction, String tooltip) => IconButton(
      tooltip: tooltip,
      onPressed: () => _move(_page + direction),
      icon: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: SizedBox.square(
          dimension: 24,
          child: Center(
            child: HomeArtworkIcon(
              direction < 0 ? HomeArtwork.back : HomeArtwork.next,
              size: 17,
              color: BingoPalette.ink,
            ),
          ),
        ),
      ));

  Widget _card(RoleOption role) {
    final preview = role.openingLine.trim();
    final name = role.displayName;
    final action = name.runes.length > 7 ? '和搭子聊聊' : '和$name聊聊';
    return LayoutBuilder(builder: (context, constraints) {
      final avatarSize = (constraints.maxWidth * .405).clamp(80.0, 155.0);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Semantics(
            button: true,
            label: '查看$name的资料',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _open(widget.onDetail, role),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                position: DecorationPosition.foreground,
                child: AssistantAvatar(
                    role: role.name, size: avatarSize, cornerRadius: 20),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                      child: Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: BingoTypography.sectionTitle.copyWith(
                              fontSize: 21,
                              height: 1.15,
                              color: const Color(0xFF301824)))),
                  const SizedBox(width: 6),
                  const Icon(Icons.favorite_rounded,
                      color: BingoPalette.primary, size: 13),
                ]),
                const SizedBox(height: 5),
                Text('“${preview.isEmpty ? '今天想聊点什么？' : preview}”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, height: 1.35, color: Color(0xFF3A202E))),
                const SizedBox(height: 5),
                Container(
                    width: 68,
                    height: 2,
                    margin: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                        color: const Color(0x64E8799F),
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: () => _open(widget.onChat, role),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD83D6D),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 38),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                        child: Text(action,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const HomeArtworkIcon(HomeArtwork.next,
                        size: 14, color: Colors.white),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      );
    });
  }
}
