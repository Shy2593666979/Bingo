import 'dart:async';
import 'dart:math' as math;

import 'package:bingo/core/design/home_artwork_icon.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/theme/home_palette.dart';
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
  static const _greetings = [
    '今天想聊点什么？',
    '今天过得怎么样呀？',
    '今天有什么事让你笑了？',
    '最近有什么想跟我分享的？',
    '有什么想说的？我听着呢。',
    '今天有啥想吐槽的吗？',
    '最近在期待什么呀？',
    '有什么纠结的事？我们一起想想。',
    '最近听到什么好听的歌了吗？',
    '今天吃到什么好吃的了？',
    '要是现在能出去走走，你想去哪儿？',
    '最近遇到什么新鲜事了吗？',
    '今天有什么值得记住的小事？',
    '有什么好消息想跟我说吗？',
    '明天有什么打算呀？',
    '今天有没有哪一刻，觉得还挺不错的？',
    '最近有没有什么想试试的？',
    '现在心情怎么样呀？',
    '来啦，陪你说会儿话。',
    '要不要随便聊两句？',
  ];
  final _random = math.Random();
  final _slideGreetings = <int, String>{};
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
    if (page == _page) return;
    setState(() {
      _page = page;
    });
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

  String _greetingFor(int page) => _slideGreetings.putIfAbsent(
      page, () => _greetings[_random.nextInt(_greetings.length)]);

  bool _onCarouselSettled(ScrollEndNotification notification) {
    if (notification.depth == 0) {
      // A neighboring page is prepared before it enters the viewport. Keep
      // that text intact during reverse drags and the page-changed rebuild.
      _slideGreetings.removeWhere((page, _) => (page - _page).abs() > 1);
    }
    return false;
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
    final dotCount = math.min(widget.roles.length, 5);
    final firstDot =
        (_index - dotCount ~/ 2).clamp(0, widget.roles.length - dotCount);
    final height =
        (MediaQuery.sizeOf(context).width - 28).clamp(260.0, 440.0) * .54 +
            math.max(0, scale.scale(21) - 21) * 2.4 +
            math.max(0, scale.scale(14) - 14) * 4;
    final controlStyle = TextButton.styleFrom(
      minimumSize: const Size(42, 35),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: HomePalette.muted,
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
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x16B46A84),
                  blurRadius: 24,
                  offset: Offset(0, 10)),
              BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 6,
                  offset: Offset(0, 2)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: height,
              child: Stack(alignment: Alignment.center, children: [
                const Positioned.fill(
                    child: CustomPaint(painter: HomePostcardBackground())),
                NotificationListener<ScrollEndNotification>(
                  onNotification: _onCarouselSettled,
                  child: PageView.builder(
                    controller: _pages,
                    physics: _multiple
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    itemCount: _multiple ? null : 1,
                    onPageChanged: _pageChanged,
                    itemBuilder: (context, page) => _card(
                        widget.roles[page % widget.roles.length],
                        _greetingFor(page)),
                  ),
                ),
                Positioned.fill(
                    child: IgnorePointer(
                        child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: HomePalette.heroBorder),
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
            padding: const EdgeInsets.only(top: 12, bottom: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = firstDot; i < firstDot + dotCount; i++)
                Semantics(
                  button: true,
                  selected: i == _index,
                  label: '切换到${widget.roles[i].displayName}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _move(_page + i - _index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        key: ValueKey('carousel-dot-${widget.roles[i].id}'),
                        width: i == _index ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: i == _index
                              ? HomePalette.accent
                              : HomePalette.accent.withValues(alpha: .22),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1EBF0)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x09000000),
                blurRadius: 14,
                offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('今天想和谁聊聊？',
                    style: BingoTypography.sectionTitle.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: HomePalette.ink)),
              ),
              TextButton(
                  style: controlStyle,
                  onPressed: widget.onAll,
                  child: const Text('全部 ›', style: TextStyle(fontSize: 12))),
            ]),
            const SizedBox(height: 6),
            SizedBox(
              key: const ValueKey('companion-preview'),
              height: 58 + scale.scale(12) * 1.4,
              child: LayoutBuilder(
                builder: (context, constraints) => ListView.builder(
                  controller: _strip,
                  scrollDirection: Axis.horizontal,
                  itemExtent: constraints.maxWidth / 5,
                  itemCount: widget.roles.length,
                  itemBuilder: (context, index) {
                    final role = widget.roles[index];
                    final selected = index == _index;
                    final size =
                        (constraints.maxWidth / 5 - 11).clamp(32.0, 44.0);
                    return Semantics(
                      selected: selected,
                      button: true,
                      child: InkWell(
                        key: ValueKey('companion-card-${role.id}'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _move(_page + index - _index),
                        child: Column(children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: selected
                                    ? HomePalette.accent
                                    : const Color(0xFFF0E7EC),
                                width: selected ? 2 : 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                          color: HomePalette.accent
                                              .withValues(alpha: .22),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3))
                                    ]
                                  : null,
                            ),
                            child: AssistantAvatar(
                                role: role.name,
                                size: size,
                                closePortrait: true),
                          ),
                          const SizedBox(height: 5),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(role.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BingoTypography.caption.copyWith(
                                    color: selected
                                        ? HomePalette.accent
                                        : HomePalette.ink,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _card(RoleOption role, String greeting) {
    final name = role.displayName;
    final action = name.runes.length > 7 ? '和搭子聊聊' : '和$name聊聊';
    return LayoutBuilder(builder: (context, constraints) {
      final avatarSize = (constraints.maxWidth * .39).clamp(80.0, 150.0);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x189D5871),
                        blurRadius: 12,
                        offset: Offset(0, 5)),
                  ],
                ),
                position: DecorationPosition.foreground,
                child: AssistantAvatar(
                    role: role.name, size: avatarSize, cornerRadius: 20),
              ),
            ),
          ),
          const SizedBox(width: 15),
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
                              fontSize: 22,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              color: HomePalette.heroInk))),
                  const SizedBox(width: 6),
                  const Icon(Icons.favorite_rounded,
                      color: HomePalette.accent, size: 14),
                ]),
                const SizedBox(height: 7),
                Text('“$greeting”',
                    key: ValueKey('carousel-greeting-${role.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: Color(0xFF5D4C54))),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _open(widget.onChat, role),
                  style: FilledButton.styleFrom(
                    backgroundColor: HomePalette.action,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor: HomePalette.action.withValues(alpha: .35),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                        child: Text(action,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 3),
                    const HomeArtworkIcon(HomeArtwork.next,
                        size: 13, color: Colors.white),
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
