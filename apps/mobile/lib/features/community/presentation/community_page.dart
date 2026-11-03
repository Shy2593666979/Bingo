import 'package:bingo/core/theme/app_theme.dart';
import 'dart:async';

import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_detail_page.dart';
import 'package:bingo/features/community/presentation/community_widgets.dart';
import 'package:bingo/features/community/presentation/community_scene.dart';
import 'package:flutter/material.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage(
      {required this.gateway,
      required this.onPublish,
      required this.onInstalled,
      required this.onOpenCopy,
      this.referenceDesign = false,
      this.onCreateGroup,
      this.onChatCopy,
      super.key});
  final CommunityGateway gateway;
  final Future<void> Function() onPublish;
  final Future<void> Function(RoleOption) onInstalled;
  final Future<void> Function(String) onOpenCopy;
  final Future<void> Function(String)? onCreateGroup, onChatCopy;
  final bool referenceDesign;
  @override
  State<CommunityPage> createState() => CommunityPageState();
}

class CommunityPageState extends State<CommunityPage> {
  void showScope(int tab) {
    setState(() {
      _tab = tab;
      _search.clear();
    });
    unawaited(refresh());
  }

  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  int _version = 0, _tab = 0;
  int? _next;
  bool _loading = true, _failed = false, _more = false, _moreFailed = false;
  List<CommunityShare> _items = [], _hotItems = [];
  final _engaging = <String>{};
  final _installing = <String>{};
  @override
  void initState() {
    super.initState();
    if (widget.referenceDesign) _tab = 5;
    unawaited(refresh());
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 320 &&
        _next != null &&
        !_more &&
        !_loading &&
        !_moreFailed) {
      unawaited(_loadMore());
    }
  }

  @override
  void dispose() {
    _version++;
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _scope => _tab == 2
      ? 'favorites'
      : _tab == 3
          ? 'mine'
          : 'all';
  String get _sort => _tab == 1 || _tab == 5 ? 'popular' : 'latest';
  Future<void> refresh() async {
    final version = ++_version;
    setState(() {
      _loading = true;
      _failed = false;
      _more = false;
      _moreFailed = false;
      _next = null;
    });
    try {
      final result = await widget.gateway.listCommunity(
          query: _search.text.trim(), scope: _scope, sort: _sort);
      if (mounted && version == _version) {
        setState(() {
          _items = result.items;
          _next = result.nextOffset;
        });
      }
    } catch (_) {
      if (mounted && version == _version) setState(() => _failed = true);
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final next = _next;
    if (next == null || _more) return;
    final version = _version;
    setState(() {
      _more = true;
      _moreFailed = false;
    });
    try {
      final result = await widget.gateway.listCommunity(
          query: _search.text.trim(), scope: _scope, sort: _sort, offset: next);
      if (mounted && version == _version) {
        setState(() {
          final ids = _items.map((item) => item.id).toSet();
          _items.addAll(result.items.where((item) => ids.add(item.id)));
          _next = result.nextOffset;
        });
      }
    } catch (_) {
      if (mounted && version == _version) setState(() => _moreFailed = true);
    } finally {
      if (mounted && version == _version) setState(() => _more = false);
    }
  }

  Future<void> _publish() async {
    await widget.onPublish();
    if (mounted) await refresh();
  }

  Future<void> _detail(CommunityShare share) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => CommunityDetailPage(
            gateway: widget.gateway,
            shareId: share.id,
            onInstalled: widget.onInstalled,
            onOpenCopy: widget.onOpenCopy,
            referenceDesign: widget.referenceDesign,
            onChatCopy: widget.onChatCopy)));
    if (mounted) await refresh();
  }

  Future<void> _install(CommunityShare share) async {
    if (_installing.contains(share.id)) return;
    if (share.installedRoleId != null) {
      await (widget.onChatCopy ?? widget.onOpenCopy)(share.installedRoleId!);
      return;
    }
    setState(() => _installing.add(share.id));
    try {
      final role = await widget.gateway.installCompanion(share.id);
      await widget.onInstalled(role);
      final updated = await widget.gateway.getCommunityShare(share.id);
      if (mounted) {
        setState(() {
          _items = _items
              .map((item) => item.id == share.id ? updated : item)
              .toList();
          _hotItems = _hotItems
              .map((item) => item.id == share.id ? updated : item)
              .toList();
        });
        showCenterToast(context, '已加入我的搭子，可以自由编辑');
      }
    } catch (_) {
      if (mounted) showCenterToast(context, '暂时无法加入，请重试');
    } finally {
      if (mounted) setState(() => _installing.remove(share.id));
    }
  }

  Future<void> _like(CommunityShare share) async {
    if (widget.gateway is! CommunityEngagementGateway ||
        !_engaging.add(share.id)) {
      return;
    }
    try {
      await (widget.gateway as CommunityEngagementGateway)
          .likeCompanion(share.id, !share.liked);
      if (mounted) await refresh();
    } catch (_) {
      if (mounted) showCenterToast(context, '点赞未能保存，请重试');
    } finally {
      _engaging.remove(share.id);
    }
  }

  Future<void> _favorite(CommunityShare share) async {
    if (!_engaging.add(share.id)) {
      return;
    }
    try {
      await widget.gateway.favoriteCompanion(share.id, !share.favorite);
      if (mounted) await refresh();
    } catch (_) {
      if (mounted) showCenterToast(context, '收藏未能保存，请重试');
    } finally {
      _engaging.remove(share.id);
    }
  }

  @override
  Widget build(BuildContext context) => widget.referenceDesign
      ? CommunityScene(
          gateway: widget.gateway,
          items: _items,
          hotItems: _hotItems,
          tab: _tab,
          onTab: (value) {
            setState(() => _tab = value);
            unawaited(refresh());
          },
          onLike: _like,
          loading: _loading,
          failed: _failed,
          search: _search,
          installing: _installing,
          onRefresh: refresh,
          onPublish: _publish,
          onDetail: _detail,
          onInstall: _install,
          onFavorite: _favorite,
          onSearch: (query) {
            if (_search.text != query) _search.text = query;
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), refresh);
          },
          onMore: _loadMore,
          hasMore: _next != null)
      : ColoredBox(
          color: communityBackground,
          child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                  onRefresh: refresh,
                  child: CustomScrollView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                            child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 18, 20, 15),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        const Expanded(
                                            child: Text('搭子社区',
                                                style: TextStyle(
                                                    fontSize: 25,
                                                    fontWeight: FontWeight.w800,
                                                    color: communityInk))),
                                        IconButton(
                                            tooltip: '分享搭子',
                                            onPressed: _publish,
                                            icon: const Icon(
                                                Icons.ios_share_rounded,
                                                color: communityAccent))
                                      ]),
                                      const Text('遇见有趣的灵魂，也分享你的喜欢',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: communityMuted)),
                                      const SizedBox(height: 20),
                                      Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFFE1F1E7),
                                                    Color(0xFFF0EDE0)
                                                  ]),
                                              borderRadius:
                                                  BorderRadius.circular(24)),
                                          child: Row(children: [
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  const Text('让喜欢的搭子\n遇见更多人',
                                                      style: TextStyle(
                                                          fontSize: 23,
                                                          height: 1.35,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: communityInk)),
                                                  const SizedBox(height: 10),
                                                  const Text(
                                                      '分享 · 加入 · 改编 · 再分享',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: Color(
                                                              0xFF718777))),
                                                  const SizedBox(height: 14),
                                                  InkWell(
                                                      onTap: _publish,
                                                      child: const Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text('分享我的搭子',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color:
                                                                        communityAccent)),
                                                            SizedBox(width: 6),
                                                            Icon(
                                                                Icons
                                                                    .arrow_forward_rounded,
                                                                size: 16,
                                                                color:
                                                                    communityAccent)
                                                          ])),
                                                ])),
                                            const SizedBox(width: 10),
                                            Transform.rotate(
                                                angle: -.12,
                                                child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            24),
                                                    child: Image.asset(
                                                        'assets/images/bingo_logo.webp',
                                                        width: 73,
                                                        height: 73))),
                                          ])),
                                      const SizedBox(height: 18),
                                      TextField(
                                          controller: _search,
                                          maxLength: 100,
                                          onChanged: (_) {
                                            _debounce?.cancel();
                                            _debounce = Timer(
                                                const Duration(
                                                    milliseconds: 350),
                                                refresh);
                                          },
                                          decoration: InputDecoration(
                                              hintText: '搜索搭子名字或介绍',
                                              hintStyle:
                                                  const TextStyle(fontSize: 13),
                                              counterText: '',
                                              prefixIcon: const Icon(
                                                  Icons.search_rounded,
                                                  size: 21),
                                              filled: true,
                                              fillColor: Colors.white,
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                  borderSide: BorderSide.none),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12))),
                                      const SizedBox(height: 15),
                                      Wrap(children: [
                                        for (final (index, label) in [
                                          (0, '最新'),
                                          (1, '热门'),
                                          (2, '收藏'),
                                          (3, '我的发布')
                                        ])
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 8),
                                              child: ChoiceChip(
                                                  label: Text(label,
                                                      style: const TextStyle(
                                                          fontSize: 12)),
                                                  selected: _tab == index,
                                                  showCheckmark: false,
                                                  onSelected: (_) {
                                                    if (_tab != index) {
                                                      setState(
                                                          () => _tab = index);
                                                      unawaited(refresh());
                                                    }
                                                  }))
                                      ]),
                                    ]))),
                        if (_loading)
                          const SliverToBoxAdapter(
                              child: Padding(
                                  padding: EdgeInsets.all(50),
                                  child: Center(
                                      child: CircularProgressIndicator())))
                        else if (_failed)
                          SliverToBoxAdapter(
                              child: CommunityEmpty(
                                  title: '社区暂时没有连接上',
                                  description: '稍后重试，或者下拉刷新。',
                                  action: '重新加载',
                                  onAction: refresh))
                        else if (_items.isEmpty)
                          SliverToBoxAdapter(
                              child: CommunityEmpty(
                                  title: _search.text.isNotEmpty
                                      ? '没有找到这个搭子'
                                      : _tab == 2
                                          ? '收藏喜欢的搭子'
                                          : _tab == 3
                                              ? '把你的搭子介绍给大家'
                                              : '第一位分享者，会是你吗？',
                                  description: _search.text.isNotEmpty
                                      ? '换个名字或关键词试试看。'
                                      : _tab == 2
                                          ? '在搭子详情中点击收藏，就能在这里找到。'
                                          : '把自己的搭子分享出来，别人就能加入搭子并继续创作。',
                                  onAction: _search.text.isNotEmpty || _tab == 2
                                      ? null
                                      : _publish))
                        else
                          SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount:
                                              MediaQuery.sizeOf(context).width >
                                                      650
                                                  ? 3
                                                  : 2,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 14,
                                          mainAxisExtent: 290 +
                                              (MediaQuery.textScalerOf(context)
                                                          .scale(16) -
                                                      16) *
                                                  8),
                                  delegate: SliverChildBuilderDelegate(
                                      (context, index) =>
                                          _card(_items[index], index),
                                      childCount: _items.length))),
                        SliverToBoxAdapter(
                            child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Center(
                                    child: _more
                                        ? const CircularProgressIndicator()
                                        : _moreFailed
                                            ? TextButton(
                                                onPressed: _loadMore,
                                                child:
                                                    const Text('加载更多失败，点击重试'))
                                            : _next != null
                                                ? TextButton(
                                                    onPressed: _loadMore,
                                                    child: const Text('查看更多搭子'))
                                                : _items.isNotEmpty && !_loading
                                                    ? const Text(
                                                        '每一种陪伴，都可以有自己的模样',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                communityMuted))
                                                    : const SizedBox
                                                        .shrink()))),
                      ]))));

  Widget _card(CommunityShare share, int index) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(21),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: _installing.contains(share.id) ? null : () => _detail(share),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                height: 105,
                width: double.infinity,
                color: [
                  const Color(0xFFEDF1E9),
                  const Color(0xFFF4E8E4),
                  const Color(0xFFEDEAF5)
                ][index % 3],
                alignment: Alignment.center,
                child: SharedCompanionAvatar(
                    share: share, gateway: widget.gateway, size: 78)),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(share.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: communityInk)),
                          const SizedBox(height: 4),
                          Text(share.introduction,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.5,
                                  color: communityMuted)),
                          const SizedBox(height: 7),
                          Text('来自 ${share.authorName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: communityMuted)),
                          const Spacer(),
                          Row(children: [
                            const Icon(Icons.favorite_border_rounded,
                                size: 12, color: Color(0xFFC397A0)),
                            const SizedBox(width: 3),
                            Text('${share.favoriteCount}',
                                style: const TextStyle(
                                    fontSize: 10, color: communityMuted)),
                            const Spacer(),
                            Text('${share.installCount} 人加入',
                                style: const TextStyle(
                                    fontSize: 10, color: communityMuted))
                          ]),
                          const SizedBox(height: 7),
                          SizedBox(
                              width: double.infinity,
                              height: 34,
                              child: FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                      backgroundColor: BingoPalette.blush,
                                      foregroundColor: communityAccent),
                                  onPressed: share.status != 'published'
                                      ? null
                                      : _installing.contains(share.id)
                                          ? null
                                          : () => _install(share),
                                  child: Text(
                                      share.status != 'published'
                                          ? '已撤回'
                                          : _installing.contains(share.id)
                                              ? '正在加入…'
                                              : share.installedRoleId != null
                                                  ? '查看我的副本'
                                                  : '加入我的搭子',
                                      style: const TextStyle(fontSize: 11)))),
                        ]))),
          ])));
}
