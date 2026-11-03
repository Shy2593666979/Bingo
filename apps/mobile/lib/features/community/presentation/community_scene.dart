import 'package:bingo/core/design/bingo_surface.dart';
import 'package:bingo/core/design/release_ui.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_widgets.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

class CommunityScene extends StatefulWidget {
  const CommunityScene(
      {required this.gateway,
      required this.items,
      required this.hotItems,
      required this.loading,
      required this.failed,
      required this.tab,
      required this.onTab,
      required this.onRefresh,
      required this.onPublish,
      required this.onDetail,
      required this.onInstall,
      required this.onFavorite,
      required this.onLike,
      required this.search,
      required this.onSearch,
      required this.installing,
      required this.onMore,
      required this.hasMore,
      super.key});
  final CommunityGateway gateway;
  final List<CommunityShare> items, hotItems;
  final bool loading, failed, hasMore;
  final int tab;
  final ValueChanged<int> onTab;
  final Future<void> Function() onRefresh;
  final VoidCallback onPublish, onMore;
  final ValueChanged<CommunityShare> onDetail, onInstall, onFavorite, onLike;
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final Set<String> installing;
  @override
  State<CommunityScene> createState() => _CommunitySceneState();
}

class _CommunitySceneState extends State<CommunityScene> {
  bool _searching = false;
  int _category = 0;
  static const _categories = ['全部', '陪伴', '朋友', '成长', '生活'];

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: BingoPalette.ice,
      child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: [
                    ReleasePageHeader('社区', actions: [
                      IconButton(
                          tooltip: '搜索社区',
                          onPressed: () =>
                              setState(() => _searching = !_searching),
                          icon: const Icon(Icons.search_rounded, size: 23)),
                      IconButton(
                          tooltip: '分享搭子',
                          onPressed: widget.onPublish,
                          icon: const Icon(Icons.person_add_alt_1_outlined,
                              size: 23)),
                    ]),
                    if (_searching)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextField(
                              controller: widget.search,
                              onChanged: (value) {
                                setState(() => _category = 0);
                                widget.onSearch(value);
                              },
                              decoration: const InputDecoration(
                                  hintText: '搜索分享、搭子或用户',
                                  prefixIcon:
                                      Icon(Icons.search_rounded, size: 20)))),
                    const SizedBox(height: 10),
                    ReleaseSegmentedTabs(
                        tabs: const [
                          (value: 5, label: '推荐'),
                          (value: 0, label: '最新'),
                          (value: 2, label: '我的收藏'),
                          (value: 3, label: '我的分享')
                        ],
                        selected: widget.tab == 1 ? 5 : widget.tab,
                        onSelected: (value) {
                          if (widget.tab == value) return;
                          setState(() => _category = 0);
                          widget.search.clear();
                          widget.onTab(value);
                        }),
                    const SizedBox(height: 16),
                    SizedBox(
                        height: 34,
                        child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _categories.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, index) => _categoryChip(index))),
                    const SizedBox(height: 16),
                    if (widget.loading)
                      const Padding(
                          padding: EdgeInsets.all(35),
                          child: Center(child: CircularProgressIndicator()))
                    else if (widget.failed)
                      CommunityEmpty(
                          title: '社区暂时没有连接上',
                          description: '稍后重试，或者下拉刷新。',
                          action: '重新加载',
                          onAction: widget.onRefresh)
                    else if (widget.items.isEmpty)
                      CommunityEmpty(
                          title: widget.tab == 2
                              ? '收藏喜欢的搭子分享'
                              : widget.tab == 3
                                  ? '把你的搭子介绍给大家'
                                  : '还没有相关搭子分享',
                          description: widget.search.text.isNotEmpty
                              ? '换个关键词，或看看其他分类。'
                              : '分享陪伴的故事，也发现合拍的搭子。',
                          onAction: widget.tab == 2 ? null : widget.onPublish)
                    else ...[
                      for (final share in widget.items)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _post(share)),
                      if (widget.hasMore)
                        TextButton(
                            onPressed: widget.onMore,
                            child: const Text('加载更多')),
                    ],
                  ]))));

  Widget _categoryChip(int index) {
    final selected = _category == index;
    return Material(
        color: selected ? const Color(0xFFE9F8F3) : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
                color: selected ? const Color(0xFFCDE8DF) : BingoPalette.line)),
        child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() => _category = index);
              widget.onSearch(index == 0 ? '' : _categories[index]);
            },
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                child: Text(_categories[index],
                    style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? BingoPalette.primaryText
                            : BingoPalette.muted,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400)))));
  }

  Widget _post(CommunityShare share) => BingoSurface(
      radius: 15,
      key: ValueKey('community-share-${share.id}'),
      onTap: () => widget.onDetail(share),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          UserAvatar(username: share.authorName, size: 31),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(share.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${_relative(share.createdAt)} · 分享搭子',
                    style: const TextStyle(
                        fontSize: 10, color: BingoPalette.muted)),
              ])),
        ]),
        const SizedBox(height: 15),
        Text(share.title.isEmpty ? '分享我的搭子 · ${share.name}' : share.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, height: 1.55)),
        const SizedBox(height: 7),
        Text(share.introduction,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, height: 1.85, color: BingoPalette.muted)),
        if (share.hasImages) ...[
          const SizedBox(height: 13),
          ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SharedPostImage(
                      share: share,
                      gateway: widget.gateway,
                      index: 0,
                      fallback: CompanionPortrait(
                          share: share, gateway: widget.gateway)))),
        ],
        const SizedBox(height: 13),
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: BingoPalette.ice,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BingoPalette.line)),
            child: Row(children: [
              SharedCompanionAvatar(
                  share: share, gateway: widget.gateway, size: 48),
              const SizedBox(width: 11),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Flexible(
                          child: Text(share.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 6),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                              border:
                                  Border.all(color: const Color(0xFFD4E5DD)),
                              borderRadius: BorderRadius.circular(3)),
                          child: const Text('AI',
                              style: TextStyle(
                                  fontSize: 8, color: Color(0xFF87AA9D)))),
                    ]),
                    const SizedBox(height: 5),
                    Text(
                        [
                          if (share.roleType?.isNotEmpty ?? false)
                            share.roleType!,
                          ...share.traits.take(1)
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: BingoPalette.muted)),
                  ])),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Color(0xFF9AAA9F)),
            ])),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(
              child: Wrap(spacing: 8, runSpacing: 5, children: [
            _action(
                share.liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                share.likeCount,
                () => widget.onLike(share),
                '点赞',
                share.liked ? BingoPalette.rose : BingoPalette.muted),
          ])),
          const SizedBox(width: 8),
          OutlinedButton(
              key: ValueKey('community-install-${share.id}'),
              onPressed: widget.installing.contains(share.id) ||
                      share.status != 'published'
                  ? null
                  : () => widget.onInstall(share),
              style: OutlinedButton.styleFrom(
                  foregroundColor: share.installedRoleId == null
                      ? BingoPalette.primaryText
                      : BingoPalette.muted,
                  backgroundColor: share.installedRoleId == null
                      ? const Color(0xFFF2FCF8)
                      : const Color(0xFFF2F5F4),
                  side: BorderSide(
                      color: share.installedRoleId == null
                          ? const Color(0xFFB7E5D8)
                          : BingoPalette.line),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 11)),
              child: Text(widget.installing.contains(share.id)
                  ? '正在添加…'
                  : share.installedRoleId == null
                      ? '+ 添加搭子'
                      : '已添加')),
        ]),
      ]));

  Widget _action(IconData icon, int count, VoidCallback onTap, String label,
          Color color) =>
      Semantics(
          label: '$label $count',
          button: true,
          child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 1),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 4),
                    Text(_count(count),
                        style: TextStyle(fontSize: 10, color: color))
                  ]))));
  String _count(int value) => value >= 10000
      ? '${(value / 10000).toStringAsFixed(1)}万'
      : value >= 1000
          ? '${(value / 1000).toStringAsFixed(1)}k'
          : '$value';
  String _relative(DateTime time) {
    final diff = DateTime.now().toUtc().difference(time.toUtc());
    return diff.inDays > 0
        ? '${diff.inDays}天前'
        : diff.inHours > 0
            ? '${diff.inHours}小时前'
            : diff.inMinutes > 0
                ? '${diff.inMinutes}分钟前'
                : '刚刚';
  }
}
