import 'package:bingo/core/design/companion_launch_ui.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_widgets.dart';
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
      this.onPartners,
      super.key});
  final CommunityGateway gateway;
  final List<CommunityShare> items, hotItems;
  final bool loading, failed, hasMore;
  final int tab;
  final ValueChanged<int> onTab;
  final Future<void> Function() onRefresh;
  final VoidCallback onPublish, onMore;
  final VoidCallback? onPartners;
  final ValueChanged<CommunityShare> onDetail, onInstall, onFavorite, onLike;
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final Set<String> installing;
  @override
  State<CommunityScene> createState() => _CommunitySceneState();
}

class _CommunitySceneState extends State<CommunityScene> {
  int _category = 0;
  static const _categories = ['推荐', '朋友', '学习', '生活'];
  void _scope(int tab) {
    setState(() => _category = 0);
    widget.search.clear();
    widget.onTab(tab);
  }

  Future<void> _creator() async {
    final value = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        backgroundColor: Colors.white,
        builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final entry in [
                (3, Icons.edit_note_rounded, '我的分享'),
                (2, Icons.favorite_border_rounded, '我的收藏'),
                (4, Icons.add_rounded, '分享搭子')
              ])
                ListTile(
                    leading: Icon(entry.$2),
                    title: Text(entry.$3),
                    onTap: () => Navigator.pop(sheet, entry.$1)),
            ])));
    if (!mounted || value == null) return;
    if (value == 4) {
      widget.onPublish();
    } else {
      _scope(value);
    }
  }

  Widget _headerButton(String title, IconData icon, VoidCallback? onTap,
          {bool chevron = false}) =>
      OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
              foregroundColor: BingoPalette.ink,
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.symmetric(
                  horizontal: CompanionLaunch.narrow(context) ? 8 : 12),
              side: const BorderSide(color: Color(0xFFF1F1F1)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(23))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 18,
                color: chevron ? BingoPalette.primary : BingoPalette.ink),
            const SizedBox(width: 6),
            Text(title,
                style: CompanionLaunch.text(13, weight: FontWeight.w600)),
            if (chevron) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFAAAAAA), size: 16)
            ],
          ]));

  @override
  Widget build(BuildContext context) {
    final personal = widget.tab == 2 || widget.tab == 3;
    return ColoredBox(
        color: BingoPalette.pageBottom,
        child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
                onRefresh: widget.onRefresh,
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                          child: Row(children: [
                            Tooltip(
                                message: '我的社区',
                                child: _headerButton(
                                    '创作者', Icons.auto_awesome_rounded, _creator,
                                    chevron: true)),
                            const Spacer(),
                            _headerButton(
                                '好友', Icons.people_rounded, widget.onPartners),
                            const SizedBox(width: 10),
                            SizedBox.square(
                                dimension: 40,
                                child: FilledButton(
                                    onPressed: widget.onPublish,
                                    style: FilledButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(40, 40),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(23))),
                                    child: const Tooltip(
                                        message: '分享搭子',
                                        child: Icon(Icons.add_rounded,
                                            size: 26)))),
                          ])),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: TextField(
                              controller: widget.search,
                              onChanged: (value) {
                                setState(() => _category = 0);
                                widget.onSearch(value);
                              },
                              style: CompanionLaunch.text(14),
                              decoration: InputDecoration(
                                  hintText: '搜索搭子',
                                  fillColor: Colors.white,
                                  hintStyle: CompanionLaunch.text(14,
                                      color: const Color(0xFF999999)),
                                  prefixIcon: const Icon(Icons.search_rounded,
                                      size: 22),
                                  prefixIconConstraints: const BoxConstraints(
                                      minWidth: 36, minHeight: 36),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  isDense: true,
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(23),
                                      borderSide: const BorderSide(
                                          color: BingoPalette.line)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(23),
                                      borderSide: const BorderSide(
                                          color: BingoPalette.primary))))),
                      const SizedBox(height: 12),
                      SizedBox(
                          height: 32 +
                              (MediaQuery.textScalerOf(context).scale(15) -
                                      15) *
                                  1.35,
                          child: ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              scrollDirection: Axis.horizontal,
                              itemCount: _categories.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, index) => _categoryChip(index))),
                      Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 28),
                              child: Row(children: [
                                if (personal)
                                  Expanded(
                                      child: Text(
                                          widget.tab == 2
                                              ? '我的收藏'
                                              : widget.tab == 3
                                                  ? '我的分享'
                                                  : '',
                                          style: CompanionLaunch.text(18,
                                              weight: FontWeight.w600))),
                                if (personal)
                                  TextButton(
                                      onPressed: () => _scope(5),
                                      child: const Text('返回广场'))
                                else ...[
                                  const Expanded(
                                      child: Text('全部搭子',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600))),
                                  _sort('最新', 0),
                                  const SizedBox(width: 28),
                                  _sort('最热', 5),
                                ],
                              ]))),
                      if (widget.loading && widget.items.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(35),
                            child: Center(child: CircularProgressIndicator()))
                      else if (widget.failed && widget.items.isEmpty)
                        CommunityEmpty(
                            title: '社区暂时没有连接上',
                            description: '稍后重试，或者下拉刷新。',
                            action: '重新加载',
                            onAction: widget.onRefresh)
                      else if (widget.items.isEmpty)
                        CommunityEmpty(
                            title: personal ? '这里还没有搭子分享' : '还没有相关搭子分享',
                            description: widget.search.text.isEmpty
                                ? '分享你的搭子，也发现合拍的朋友。'
                                : '试试其他关键词。',
                            onAction: widget.tab == 2 ? null : widget.onPublish)
                      else ...[
                        for (final share in widget.items) _post(share),
                        if (widget.hasMore)
                          TextButton(
                              onPressed: widget.onMore,
                              child: const Text('加载更多')),
                      ],
                    ]))));
  }

  Widget _sort(String label, int value) {
    final selected = widget.tab == value;
    return InkWell(
        onTap: () => _scope(value),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: BingoTypography.body.copyWith(
                  color: selected ? BingoPalette.ink : BingoPalette.muted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          const SizedBox(height: 3),
          Container(
              width: 28,
              height: 2,
              decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(2))),
        ]));
  }

  Widget _categoryChip(int index) {
    final selected = _category == index;
    return Material(
        color: selected ? BingoPalette.primary : Colors.white,
        shape: StadiumBorder(
            side: BorderSide(
                color:
                    selected ? BingoPalette.primary : const Color(0xFFF1F1F1))),
        child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              setState(() => _category = index);
              widget.onSearch(
                  index == 0 ? '' : const ['', '朋友', '学习', '生活'][index]);
            },
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Text(_categories[index],
                    style: CompanionLaunch.text(14,
                        color: selected ? Colors.white : BingoPalette.ink,
                        weight: FontWeight.w400)))));
  }

  Widget _post(CommunityShare share) {
    final tags =
        (share.shareTags.isNotEmpty ? share.shareTags : share.traits).take(3);
    return Padding(
        key: ValueKey('community-share-${share.id}'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: BingoPalette.line)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: () => widget.onDetail(share),
                child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SharedCompanionAvatar(
                                    share: share,
                                    gateway: widget.gateway,
                                    size: 68),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text.rich(
                                                TextSpan(children: [
                                                  TextSpan(
                                                      text: share.name,
                                                      style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: BingoPalette
                                                              .ink)),
                                                  TextSpan(
                                                      text:
                                                          ' @${share.authorName}',
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color: BingoPalette
                                                              .muted))
                                                ]),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                        const SizedBox(width: 4),
                                        TextButton(
                                            onPressed: widget.installing
                                                        .contains(share.id) ||
                                                    share.installedRoleId !=
                                                        null
                                                ? null
                                                : () => widget.onInstall(share),
                                            style: TextButton.styleFrom(
                                                minimumSize: const Size(0, 24),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 2),
                                                backgroundColor:
                                                    const Color(0xFFFFF0F5),
                                                foregroundColor:
                                                    BingoPalette.primary,
                                                disabledForegroundColor:
                                                    BingoPalette.muted,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap),
                                            child: Text(
                                                widget.installing
                                                        .contains(share.id)
                                                    ? '添加中'
                                                    : share.installedRoleId != null
                                                        ? '已添加'
                                                        : '添加',
                                                style: const TextStyle(fontSize: 11))),
                                        const Icon(Icons.chevron_right_rounded,
                                            size: 16, color: BingoPalette.muted)
                                      ]),
                                      const SizedBox(height: 5),
                                      Text(share.introduction,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              height: 1.5,
                                              color: BingoPalette.ink)),
                                    ]))
                              ]),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            CommunityTags(tags.toList())
                          ],
                        ])))));
  }
}
