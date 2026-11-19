import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_widgets.dart';
import 'package:flutter/material.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({required this.gateway, required this.onOpen, super.key});
  final CommunityGateway gateway;
  final Future<void> Function(String) onOpen;
  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<CommunityShare> _items = [];
  final _removing = <String>{};
  Timer? _searchTimer;
  String _query = '';
  int _version = 0;
  int? _next, _total;
  bool _loading = true, _moreLoading = false, _failed = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_next == null || _moreLoading || _loading)) return;
    final offset = more ? _next! : 0;
    final version = more ? _version : ++_version;
    setState(() {
      if (more) {
        _moreLoading = true;
      } else {
        _loading = true;
        _moreLoading = false;
      }
      _failed = false;
    });
    try {
      final result = await widget.gateway.listCommunity(
          scope: 'favorites', query: _query, sort: 'latest', offset: offset);
      if (!mounted || version != _version) return;
      setState(() {
        final rows = more ? [..._items, ...result.items] : result.items;
        _items = {for (final item in rows) item.id: item}.values.toList();
        _next = result.nextOffset;
        _total = result.total;
      });
    } catch (_) {
      if (mounted && version == _version) {
        if (more) {
          showCenterToast(context, '加载未成功，请重试');
        } else {
          setState(() => _failed = true);
        }
      }
    } finally {
      if (mounted && version == _version) {
        setState(() {
          _loading = false;
          _moreLoading = false;
        });
      }
    }
  }

  void _search(String value) {
    _searchTimer?.cancel();
    _query = value.trim();
    _version++; // Invalidate responses for the preceding search immediately.
    _searchTimer = Timer(const Duration(milliseconds: 300), () => _load());
  }

  Future<void> _remove(CommunityShare share) async {
    if (_removing.contains(share.id)) return;
    setState(() => _removing.add(share.id));
    try {
      await widget.gateway.favoriteCompanion(share.id, false);
      if (!mounted) return;
      setState(() => _items.removeWhere((item) => item.id == share.id));
      showCenterToast(context, '已取消收藏');
      // Removing an item shifts the server's offset pagination.
      await _load();
    } catch (_) {
      if (mounted) showCenterToast(context, '取消收藏未成功，请重试');
    } finally {
      if (mounted) setState(() => _removing.remove(share.id));
    }
  }

  Future<void> _open(CommunityShare share) async {
    await widget.onOpen(share.id);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('我的收藏'), centerTitle: true),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                TextField(
                    onChanged: _search,
                    decoration: const InputDecoration(
                        hintText: '搜索收藏的搭子',
                        prefixIcon: Icon(Icons.search_rounded, size: 22))),
                const SizedBox(height: 24),
                if (_loading)
                  const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()))
                else if (_failed)
                  Column(children: [
                    const Text('收藏加载失败，请重试'),
                    TextButton(onPressed: _load, child: const Text('重新加载'))
                  ])
                else if (_items.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 54),
                      child: Column(children: [
                        Icon(Icons.bookmark_border_rounded,
                            size: 36,
                            color: BingoPalette.primary.withValues(alpha: .55)),
                        const SizedBox(height: 16),
                        Text(_query.isEmpty ? '还没有收藏的搭子' : '没有找到相关收藏',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 9),
                        Text(
                            _query.isEmpty
                                ? '在分享详情中收藏喜欢的搭子，就能在这里找到。'
                                : '试试其他名字或关键词。',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: BingoPalette.muted)),
                      ]))
                else ...[
                  Text('收藏的搭子 · ${_total ?? _items.length}',
                      style: const TextStyle(
                          fontSize: 13, color: BingoPalette.muted)),
                  const SizedBox(height: 12),
                  for (final item in _items)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side:
                                    const BorderSide(color: BingoPalette.line)),
                            child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _open(item),
                                child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        14, 16, 6, 16),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SharedCompanionAvatar(
                                              share: item,
                                              gateway: widget.gateway,
                                              size: 60),
                                          const SizedBox(width: 13),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(item.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const SizedBox(height: 4),
                                                Text('来自 ${item.authorName}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: BingoPalette
                                                            .muted)),
                                                const SizedBox(height: 7),
                                                Text(item.introduction,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        height: 1.6,
                                                        color:
                                                            Color(0xFF777177))),
                                              ])),
                                          IconButton(
                                              tooltip: '取消收藏 ${item.name}',
                                              onPressed:
                                                  _removing.contains(item.id)
                                                      ? null
                                                      : () => _remove(item),
                                              icon: const Icon(
                                                  Icons.bookmark_rounded,
                                                  color: BingoPalette.primary,
                                                  size: 21)),
                                        ]))))),
                  if (_next != null)
                    TextButton(
                        onPressed:
                            _moreLoading ? null : () => _load(more: true),
                        child: Text(_moreLoading ? '加载中…' : '加载更多')),
                ],
              ])));
}
