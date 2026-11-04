import 'package:bingo/core/design/companion_launch_ui.dart';
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
  Widget build(BuildContext context) => DecoratedBox(
      decoration: CompanionLaunch.background,
      child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    CompanionLaunchHeader('社区', actions: [
                      IconButton(
                          tooltip: '搜索社区',
                          onPressed: () =>
                              setState(() => _searching = !_searching),
                          icon: const Icon(Icons.search_rounded, size: 26)),
                    ]),
                    CompanionLaunchTabs(
                        tabs: [
                          (value: 5, label: '推荐'),
                          (value: 0, label: '最新'),
                          (
                            value: widget.tab == 3 ? 3 : 2,
                            label: widget.tab == 3 ? '我的分享' : '收藏'
                          ),
                        ],
                        selected: widget.tab == 1 ? 5 : widget.tab,
                        onSelected: (value) {
                          if (widget.tab == value) return;
                          setState(() => _category = 0);
                          widget.search.clear();
                          widget.onTab(value);
                        }),
                    if (_searching)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                          child: Column(children: [
                            TextField(
                                controller: widget.search,
                                onChanged: (value) {
                                  setState(() => _category = 0);
                                  widget.onSearch(value);
                                },
                                decoration: const InputDecoration(
                                    hintText: '搜索分享、搭子或用户',
                                    prefixIcon:
                                        Icon(Icons.search_rounded, size: 20))),
                            const SizedBox(height: 12),
                            SizedBox(
                                height: 34,
                                child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _categories.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (_, index) =>
                                        _categoryChip(index))),
                            Align(
                                alignment: Alignment.centerRight,
                                child: Tooltip(
                                    message: '分享搭子',
                                    child: TextButton.icon(
                                        onPressed: widget.onPublish,
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 18),
                                        label: const Text('分享搭子')))),
                          ])),
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
                      for (final share in widget.items) ...[
                    Padding(padding: EdgeInsets.zero, child: _post(share)),
                        Container(height: 8, color: CompanionLaunch.tint),
                      ],
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

  Widget _post(CommunityShare share) {
    final compact = CompanionLaunch.compact(context);
    final installed = share.installedRoleId != null;
    final available =
        !widget.installing.contains(share.id) && share.status == 'published';
    return Material(
        key: ValueKey('community-share-${share.id}'),
        color: Colors.white,
        child: Padding(
            padding: EdgeInsets.fromLTRB(
                compact ? 17 : 22, 12, compact ? 17 : 22, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                UserAvatar(
                    username: share.authorName,
                    size: 40,
                    backgroundColor: share.authorName.hashCode.isEven
                        ? const Color(0xFF28BA6D)
                        : const Color(0xFF7BCC50),
                    foregroundColor: Colors.white),
                const SizedBox(width: 13),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(share.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CompanionLaunch.text(compact ? 17 : 18,
                              weight: FontWeight.w700)),
                      Text(_relative(share.createdAt),
                          style: CompanionLaunch.text(12,
                              color: const Color(0xFF8A9C8D))),
                    ])),
                IconButton(
                    tooltip: '查看分享',
                    onPressed: () => widget.onDetail(share),
                    icon: const Icon(Icons.more_horiz, size: 22)),
              ]),
              const SizedBox(height: 13),
              InkWell(
                  onTap: () => widget.onDetail(share),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (share.title.isNotEmpty) ...[
                          Text(share.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: CompanionLaunch.text(compact ? 16 : 18,
                                  weight: FontWeight.w600)),
                          const SizedBox(height: 5),
                        ],
                        Text(share.introduction,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: CompanionLaunch.text(compact ? 16 : 18,
                                height: 1.5)),
                      ])),
              if (share.hasImages) ...[
                const SizedBox(height: 13),
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: SharedPostImage(
                            share: share,
                            gateway: widget.gateway,
                            index: 0,
                            fallback: CompanionPortrait(
                                share: share, gateway: widget.gateway)))),
              ],
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF0FBF5),
                      border: Border.all(color: const Color(0xFFE3F2E8)),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Expanded(
                        child: InkWell(
                            onTap: () => widget.onDetail(share),
                            borderRadius: BorderRadius.circular(14),
                            child: Row(children: [
                              SharedCompanionAvatar(
                                  share: share,
                                  gateway: widget.gateway,
                                  size: compact ? 66 : 80),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(share.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: CompanionLaunch.text(
                                            compact ? 17 : 19,
                                            weight: FontWeight.w700)),
                                    if (share.roleType?.isNotEmpty == true)
                                      Text(share.roleType!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: CompanionLaunch.text(11,
                                              color: const Color(0xFF398761))),
                                    Text(companionShareDescription(share),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: CompanionLaunch.text(
                                            compact ? 12 : 14,
                                            color: const Color(0xFF54705B),
                                            height: 1.4)),
                                  ])),
                            ]))),
                    const SizedBox(width: 8),
                    if (installed)
                      TextButton(
                          key: ValueKey('community-install-${share.id}'),
                          onPressed:
                              available ? () => widget.onInstall(share) : null,
                          child:
                              const Text('已添加', style: TextStyle(fontSize: 12)))
                    else
                      CompanionLaunchButton(
                          key: ValueKey('community-install-${share.id}'),
                          label: widget.installing.contains(share.id)
                              ? '正在添加…'
                              : '添加搭子',
                          onPressed:
                              available ? () => widget.onInstall(share) : null),
                  ])),
              const SizedBox(height: 9),
              Row(children: [
                _social(
                    share.liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    '点赞 ${_count(share.likeCount)}',
                    () => widget.onLike(share),
                    active: share.liked),
                _social(
                    Icons.chat_bubble_outline_rounded,
                    '评论 ${_count(share.commentCount)}',
                    () => widget.onDetail(share)),
                _social(
                    share.favorite
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    share.favorite ? '已收藏' : '收藏',
                    () => widget.onFavorite(share),
                    active: share.favorite,
                    right: true),
              ]),
            ])));
  }

  Widget _social(IconData icon, String label, VoidCallback onTap,
          {bool active = false, bool right = false}) =>
      Expanded(
          child: Align(
              alignment: right ? Alignment.centerRight : Alignment.centerLeft,
              child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(icon,
                                size: 20,
                                color: active
                                    ? CompanionLaunch.primary
                                    : const Color(0xFF294B34)),
                            const SizedBox(width: 6),
                            Text(label,
                                style: CompanionLaunch.text(12,
                                    color: active
                                        ? CompanionLaunch.primary
                                        : const Color(0xFF718574))),
                          ]))))));

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
