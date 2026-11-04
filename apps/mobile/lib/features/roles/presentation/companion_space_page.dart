import 'package:bingo/core/design/companion_launch_ui.dart';
import 'package:bingo/core/design/companion_menu_icon.dart';
import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/design/bingo_icon.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/core/widgets/unread_badge.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_widgets.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/roles/data/local_role_order_store.dart';
import 'package:bingo/features/stickers/sticker.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/group_avatar.dart';
import 'package:flutter/material.dart';

class CompanionSpacePage extends StatefulWidget {
  const CompanionSpacePage(
      {required this.gateway,
      required this.groups,
      required this.userId,
      required this.onChat,
      required this.onDetail,
      required this.onOpenGroup,
      required this.onCreateGroup,
      required this.onCreateRole,
      required this.onAllGroups,
      required this.onCommunity,
      required this.onMessages,
      required this.onSearchChats,
      this.community,
      this.onRecommendation,
      this.onInstalled,
      super.key});
  final RoleGateway gateway;
  final GroupGateway groups;
  final CommunityGateway? community;
  final String userId;
  final Future<void> Function(RoleOption) onChat, onDetail;
  final Future<void> Function(ChatGroup) onOpenGroup;
  final Future<void> Function(String) onCreateGroup;
  final Future<void> Function() onCreateRole;
  final Future<void> Function(String)? onRecommendation;
  final Future<void> Function()? onInstalled;
  final VoidCallback onAllGroups, onCommunity, onMessages, onSearchChats;
  @override
  State<CompanionSpacePage> createState() => CompanionSpacePageState();
}

class CompanionSpacePageState extends State<CompanionSpacePage> {
  double _refreshTurns = 0;
  bool _refreshAnimating = false;

  Future<void> _refreshRecommendation() async {
    if (_recLoading || _adding != null || _refreshAnimating) return;
    setState(() {
      _refreshTurns += 1;
      _refreshAnimating = true;
    });
    try {
      await Future.wait([
        _changeRecommendation(),
        Future<void>.delayed(const Duration(milliseconds: 600)),
      ]);
    } finally {
      if (mounted) setState(() => _refreshAnimating = false);
    }
  }

  List<RoleOption>? _roles;
  List<ChatGroup> _groups = [];
  List<CommunityShare> _recommendations = [];
  int? _nextRecommendationOffset;
  int _recommendationRotations = 0;
  final _consumed = <String>{};
  bool _failed = false,
      _loading = false,
      _recLoading = false,
      _recFailed = false;
  String? _adding;
  int _version = 0, _recVersion = 0;
  final _order = const AndroidLocalRoleOrderStore();
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(covariant CompanionSpacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _version++;
      _recVersion++;
      _loading = false;
      _recLoading = false;
      _roles = null;
      _groups = [];
      _recommendations = [];
      _nextRecommendationOffset = null;
      _recommendationRotations = 0;
      _consumed.clear();
      _adding = null;
      unawaited(refresh());
    }
  }

  Future<void> createCompanion() => widget.onCreateRole();
  Future<void> refresh({bool recommendations = true}) async {
    if (_loading) return;
    _loading = true;
    final version = ++_version;
    if (recommendations) unawaited(_loadRecommendations());
    try {
      final result = await Future.wait<Object>(
          [widget.gateway.listRoles(), widget.groups.listGroups()]);
      List<String> order = [];
      try {
        order = await _order.load(widget.userId);
      } catch (_) {}
      if (!mounted || version != _version) return;
      setState(() {
        _roles = applyLocalRoleOrder(result[0] as List<RoleOption>, order);
        _groups = result[1] as List<ChatGroup>;
        _failed = false;
        _consumed.addAll(
            _roles!.map((r) => r.sourcePublicationId).whereType<String>());
        _recommendations.removeWhere((s) => _consumed.contains(s.id));
      });
    } catch (_) {
      if (mounted && version == _version) setState(() => _failed = true);
    } finally {
      if (version == _version) _loading = false;
    }
  }

  Future<void> _loadRecommendations({int offset = 0}) async {
    final gateway = widget.community;
    if (gateway == null || _recLoading) return;
    final version = ++_recVersion;
    setState(() {
      _recLoading = true;
      _recFailed = false;
    });
    try {
      final result = await gateway.listCommunity(
          scope: 'recommended', sort: 'popular', offset: offset);
      if (!mounted || version != _recVersion) return;
      setState(() {
        _nextRecommendationOffset = result.nextOffset;
        _recommendationRotations = 0;
        _recommendations = result.items
            .where((s) =>
                !s.mine &&
                s.status == 'published' &&
                s.installedRoleId == null &&
                !_consumed.contains(s.id))
            .toList();
      });
    } catch (_) {
      if (mounted && version == _recVersion) setState(() => _recFailed = true);
    } finally {
      if (mounted && version == _recVersion) {
        setState(() => _recLoading = false);
      }
    }
  }

  Future<void> _changeRecommendation() async {
    if (_recLoading || _adding != null) return;
    final previous = _recommendations.firstOrNull?.id;
    if (_recommendations.length > 1 &&
        (_nextRecommendationOffset == null ||
            _recommendationRotations < _recommendations.length - 1)) {
      setState(() {
        _recommendations.add(_recommendations.removeAt(0));
        _recommendationRotations++;
      });
      return;
    }
    await _loadRecommendations(offset: _nextRecommendationOffset ?? 0);
    if (!mounted || _recFailed) return;
    if (_recommendations.length > 1 && _recommendations.first.id == previous) {
      setState(() => _recommendations.add(_recommendations.removeAt(0)));
    } else if (_recommendations.length == 1 &&
        _recommendations.first.id == previous) {
      showCenterToast(context, '暂时没有其他推荐搭子了');
    }
  }

  Future<void> _install(CommunityShare share) async {
    if (_adding != null || widget.community == null) return;
    final user = widget.userId;
    setState(() => _adding = share.id);
    try {
      final role = await widget.community!.installCompanion(share.id);
      if (!mounted || user != widget.userId) return;
      setState(() {
        _consumed.add(share.id);
        _recommendations.removeWhere((s) => s.id == share.id);
        if (!(_roles ?? []).any((r) => r.id == role.id)) {
          _roles = [...?_roles, role];
        }
      });
      showCenterToast(context, '已加入我的搭子');
      if (_recommendations.isEmpty) unawaited(_loadRecommendations());
      // Refresh failures must not turn a successful install into a retry.
      try {
        await widget.onInstalled?.call();
      } catch (_) {}
    } catch (_) {
      if (mounted && user == widget.userId) {
        showCenterToast(context, '添加未成功，请重试');
      }
    } finally {
      if (mounted && user == widget.userId) setState(() => _adding = null);
    }
  }

  Future<void> _openRecommendation(CommunityShare share) async {
    if (widget.onRecommendation == null) {
      widget.onCommunity();
      return;
    }
    await widget.onRecommendation!(share.id);
    if (mounted) await refresh();
  }

  Widget _heading(String text, VoidCallback? more,
          {String label = '全部 ›',
          int? count,
          bool refresh = false,
          double top = 27,
          double bottom = 18}) =>
      Padding(
          padding: EdgeInsets.only(top: top, bottom: bottom),
          child: Row(children: [
            Expanded(
                child: Row(children: [
              Flexible(
                  child: Text(text,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700))),
              if (count != null) ...[
                const SizedBox(width: 7),
                Text('$count',
                    style: const TextStyle(
                        fontSize: 12, color: BingoPalette.muted))
              ],
            ])),
            if (more != null)
              if (refresh)
                IconButton(
                    tooltip: '换一个',
                    onPressed:
                        _recLoading || _refreshAnimating || _adding != null
                            ? null
                            : more,
                    style: IconButton.styleFrom(
                        minimumSize: const Size(32, 26),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    icon: AnimatedRotation(
                        turns: _refreshTurns,
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeInOutCubic,
                        child: const CompanionMenuIcon(
                            CompanionMenuSymbol.refresh,
                            size: 20,
                            color: CompanionLaunch.primary)))
              else
                TextButton(
                    onPressed: more,
                    style: TextButton.styleFrom(
                        minimumSize: const Size(44, 26),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w400),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 12, color: BingoPalette.muted)))
          ]));
  void _allPartners() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
          child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(children: [
                      const Expanded(
                          child: Text('我的搭子',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600))),
                      IconButton(
                          onPressed: () => Navigator.pop(sheet),
                          icon: const Icon(Icons.close))
                    ])),
                Expanded(
                    child: ListView(children: [
                  for (final role in _roles ?? <RoleOption>[])
                    ListTile(
                        leading: AssistantAvatar(role: role.name, size: 44),
                        title: Text(role.displayName),
                        subtitle: Text(role.cardDescription,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(sheet);
                          widget.onDetail(role);
                        })
                ]))
              ]))));
  Widget _partners() {
    final compact = CompanionLaunch.compact(context);
    final size = compact ? 62.0 : 68.0;
    final textSize = compact ? 14.0 : 16.0;
    return SizedBox(
        height:
            size + 9 + MediaQuery.textScalerOf(context).scale(textSize) * 1.5,
        child: ListView.builder(
            key: const ValueKey('companion-strip-0'),
            scrollDirection: Axis.horizontal,
            itemExtent: size + 12,
            itemCount: _roles!.length,
            itemBuilder: (_, i) {
              final role = _roles![i];
              return Padding(
                  key: ValueKey('companion-card-${role.id}'),
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                      onTap: () => widget.onDetail(role),
                      borderRadius: BorderRadius.circular(17),
                      child: Column(children: [
                        AssistantAvatar(role: role.name, size: size),
                        const SizedBox(height: 9),
                        Text(role.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CompanionLaunch.text(textSize,
                                weight: FontWeight.w500)),
                      ])));
            }));
  }

  Widget _discover() {
    final share = _recommendations.firstOrNull;
    final gateway = widget.community;
    final compact = CompanionLaunch.compact(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('发现搭子', () => unawaited(_refreshRecommendation()),
          top: 16, bottom: 11, refresh: true),
      if (share != null && gateway != null)
        Container(
            padding: const EdgeInsets.fromLTRB(5, 9, 7, 9),
            decoration: BoxDecoration(
                color: const Color(0xFFF9FEFB),
                border: Border.all(color: const Color(0xFFE1F0E6)),
                borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              InkWell(
                  onTap: () => _openRecommendation(share),
                  borderRadius: BorderRadius.circular(18),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox.square(
                          dimension: compact ? 76 : 88,
                          child: CompanionPortrait(
                              share: share, gateway: gateway)))),
              SizedBox(width: compact ? 9 : 12),
              Expanded(
                  child: InkWell(
                      onTap: () => _openRecommendation(share),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(share.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CompanionLaunch.text(compact ? 17 : 19,
                                    weight: FontWeight.w700, height: 1.35)),
                            Text(
                                [
                                  if (share.roleType?.isNotEmpty == true)
                                    share.roleType!,
                                  '${share.authorName}分享'
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CompanionLaunch.text(compact ? 12 : 14,
                                    color: const Color(0xFF718777))),
                            const SizedBox(height: 3),
                            Text(companionShareDescription(share),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: CompanionLaunch.text(compact ? 14 : 16,
                                    color: const Color(0xFF395E46),
                                    height: 1.45)),
                          ]))),
              const SizedBox(width: 7),
              CompanionLaunchButton(
                  key: ValueKey('recommend-add-${share.id}'),
                  label: _adding == share.id ? '添加中' : '添加',
                  onPressed: _adding != null ? null : () => _install(share)),
            ]))
      else
        Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(children: [
              Expanded(
                  child: Text(
                      _recLoading
                          ? '正在寻找新的搭子'
                          : _recFailed
                              ? '推荐暂时加载失败'
                              : '去社区发现更多有趣的搭子',
                      style: CompanionLaunch.text(12,
                          color: CompanionLaunch.muted))),
              TextButton(
                  onPressed: _recLoading
                      ? null
                      : _recFailed
                          ? _loadRecommendations
                          : widget.onCommunity,
                  child: Text(_recFailed ? '重试' : '去看看')),
            ])),
    ]);
  }

  String _clock(DateTime? time) {
    if (time == null) return '';
    final t = time.toUtc().add(const Duration(hours: 8));
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return (t.year == now.year && t.month == now.month && t.day == now.day)
        ? '${t.hour}:${t.minute.toString().padLeft(2, '0')}'
        : '${t.month}/${t.day}';
  }

  Widget _recentRow(
          {required Widget avatar,
          required String name,
          required String preview,
          required DateTime? date,
          required int unread,
          required VoidCallback onTap,
          bool group = false}) =>
      InkWell(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: BingoPalette.line))),
              child: Row(children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Flexible(
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700))),
                        if (group) ...[
                          const SizedBox(width: 6),
                          const BingoIcon(BingoSymbol.group,
                              size: 17, color: BingoPalette.muted)
                        ]
                      ]),
                      const SizedBox(height: 2),
                      Text(ChatSticker.preview(preview),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, color: CompanionLaunch.muted))
                    ])),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_clock(date),
                      style: const TextStyle(
                          fontSize: 11, color: BingoPalette.muted)),
                  if (unread > 0) ...[
                    const SizedBox(height: 7),
                    UnreadBadge(count: unread)
                  ]
                ])
              ])));
  List<Widget> _recentChats() {
    final recent = <({DateTime date, Widget child})>[];
    for (final g
        in _groups.where((g) => !g.archived && g.lastMessage != null)) {
      recent.add((
        date: g.lastActivity,
        child: _recentRow(
            avatar: GroupAvatar(members: g.activeMembers, size: 50),
            name: g.name,
            preview:
                '${g.senderNameFor(g.lastMessage!)}：${g.lastMessage!.content}',
            date: g.lastActivity,
            unread: g.unread,
            group: true,
            onTap: () => widget.onOpenGroup(g))
      ));
    }
    for (final r in (_roles ?? <RoleOption>[])
        .where((r) => r.messageCount > 0 && !r.archived)) {
      recent.add((
        date: r.lastMessageAt ?? DateTime(2000),
        child: _recentRow(
            avatar: AssistantAvatar(role: r.name, size: 52),
            name: r.displayName,
            preview: r.lastMessage ?? '和搭子聊聊吧',
            date: r.lastMessageAt,
            unread: r.unreadCount,
            onTap: () => widget.onChat(r))
      ));
    }
    recent.sort((a, b) => b.date.compareTo(a.date));
    return recent.take(5).map((e) => e.child).toList();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: CompanionLaunch.background,
      child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
                  children: [
                    CompanionLaunchHeader('陪伴空间',
                        horizontalPadding: 0,
                        actions: [
                          IconButton(
                              tooltip: '查找聊天',
                              onPressed: widget.onSearchChats,
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.search_rounded, size: 26)),
                        ]),
                    const SizedBox(height: 16),
                    SizedBox(
                        height: 80,
                        child: Row(children: [
                          Expanded(
                              child: CompanionLaunchCreateAction(
                                  group: false, onTap: widget.onCreateRole)),
                          const SizedBox(width: 15),
                          Expanded(
                              child: CompanionLaunchCreateAction(
                                  group: true,
                                  onTap: () => widget.onCreateGroup(''))),
                        ])),
                    _heading('我的搭子', _allPartners),
                    if (_roles == null && !_failed)
                      const Center(child: CircularProgressIndicator())
                    else if (_failed && _roles == null)
                      TextButton(
                          onPressed: refresh, child: const Text('加载失败，点击重试'))
                    else if (_roles!.isEmpty)
                      TextButton(
                          onPressed: widget.onCreateRole,
                          child: const Text('创建自己的第一位搭子'))
                    else
                      _partners(),
                    const SizedBox(height: 15),
                    const Divider(height: 1, color: CompanionLaunch.line),
                    _discover(),
                    InkWell(
                        onTap: widget.onMessages,
                        child: _heading('最近聊天', null, top: 14, bottom: 5)),
                    ..._recentChats(),
                    if (_recentChats().isEmpty)
                      Padding(
                          padding: const EdgeInsets.all(14),
                          child: TextButton(
                              onPressed: widget.onMessages,
                              child: const Text('找搭子聊聊今天吧'))),
                  ]))));
}
