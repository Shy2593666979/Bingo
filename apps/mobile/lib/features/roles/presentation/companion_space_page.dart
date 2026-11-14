import 'package:bingo/core/design/pearl_icon.dart';
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
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:bingo/core/role_avatar_assets.dart';
import 'package:bingo/core/role_avatar_store.dart';
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
      this.onReady,
      this.showHeader = true,
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
  final VoidCallback? onReady;
  final VoidCallback onAllGroups, onCommunity, onMessages, onSearchChats;
  final bool showHeader;
  @override
  State<CompanionSpacePage> createState() => CompanionSpacePageState();
}

class CompanionSpacePageState extends State<CompanionSpacePage> {
  double _refreshTurns = 0;
  bool _refreshAnimating = false;
  bool _startupReported = false;

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
    final recommendationLoad =
        recommendations ? _loadRecommendations() : Future<void>.value();
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
      if (!_startupReported && widget.onReady != null) {
        await recommendationLoad;
        if (mounted && version == _version) {
          await _prepareHomeImages();
          await WidgetsBinding.instance.endOfFrame;
          if (mounted && version == _version) {
            _startupReported = true;
            widget.onReady?.call();
          }
        }
      }
    }
  }

  Future<void> _prepareHomeImages() async {
    ImageProvider portrait(String name) {
      final bytes = RoleAvatarStore.images.value[name];
      if (bytes != null) return MemoryImage(bytes);
      return ResizeImage.resizeIfNeeded(
          512,
          null,
          AssetImage(squareAvatarAsset(
              RoleAvatarStore.assets[name] ?? assistantAvatarAsset(name))));
    }

    final names = {
      ...?_roles?.take(6).map((r) => r.name),
      for (final group in _groups.take(2))
        ...group.activeMembers.map((m) => m.roleName),
    };
    final jobs = <Future<void>>[
      for (final name in names)
        precacheImage(portrait(name), context, onError: (_, __) {}),
      if (_recommendations.isNotEmpty)
        _prepareRecommendation(_recommendations.first),
    ];
    await Future.wait(jobs)
        .timeout(const Duration(seconds: 5), onTimeout: () => []);
  }

  Future<void> _prepareRecommendation(CommunityShare share) async {
    if (!mounted) return;
    final gateway = widget.community;
    final ImageProvider image = share.hasAvatar && gateway != null
        ? NetworkImage(gateway.communityAvatarUrl(share.id), headers: {
            if (gateway.communityAccessToken != null)
              'Authorization': 'Bearer ${gateway.communityAccessToken}',
          })
        : AssetImage(squareAvatarAsset(
            'assets/images/${roleAvatarFiles.contains(share.avatarAsset) ? share.avatarAsset : 'bingo_logo.png'}'));
    if (!share.hasAvatar && widget.onReady == null) {
      unawaited(precacheImage(image, context, onError: (_, __) {}));
      return;
    }
    await precacheImage(image, context, onError: (_, __) {})
        .timeout(const Duration(seconds: 3), onTimeout: () {});
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
      final eligible = result.items
          .where((s) =>
              !s.mine &&
              s.status == 'published' &&
              s.installedRoleId == null &&
              !_consumed.contains(s.id))
          .toList();
      if (eligible.isNotEmpty) {
        await _prepareRecommendation(eligible.first);
      }
      if (!mounted || version != _recVersion) return;
      setState(() {
        _nextRecommendationOffset = result.nextOffset;
        _recommendationRotations = 0;
        _recommendations =
            eligible.where((s) => !_consumed.contains(s.id)).toList();
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
      final version = _recVersion;
      await _prepareRecommendation(_recommendations[1]);
      if (!mounted || version != _recVersion || _recommendations.length < 2) {
        return;
      }
      setState(() {
        _recommendations.add(_recommendations.removeAt(0));
        _recommendationRotations++;
      });
      return;
    }
    await _loadRecommendations(offset: _nextRecommendationOffset ?? 0);
    if (!mounted || _recFailed) return;
    if (_recommendations.length > 1 && _recommendations.first.id == previous) {
      final version = _recVersion;
      await _prepareRecommendation(_recommendations[1]);
      if (!mounted || version != _recVersion || _recommendations.length < 2) {
        return;
      }
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
          double top = 20,
          double bottom = 12}) =>
      Padding(
          padding: EdgeInsets.only(top: top, bottom: bottom),
          child: Row(children: [
            Expanded(
                child: Row(children: [
              Flexible(
                  child: Text(text,
                      style:
                          BingoTypography.sectionTitle.copyWith(fontSize: 20))),
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
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Expanded(
                          child: Text('我的搭子',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w500))),
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
  Widget _partners() => SizedBox(
      key: const ValueKey('companion-preview'),
      height: 96 + (MediaQuery.textScalerOf(context).scale(12) - 12) * 1.35,
      child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _roles!.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            if (i == _roles!.length) {
              return InkWell(
                  onTap: widget.onCreateRole,
                  child: Column(children: [
                    Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                            color: BingoPalette.blush,
                            borderRadius: BorderRadius.circular(15)),
                        child: const Icon(Icons.add_rounded,
                            color: BingoPalette.primary, size: 28)),
                    const SizedBox(height: 7),
                    const Text('添加', style: BingoTypography.caption)
                  ]));
            }
            final role = _roles![i];
            return InkWell(
                key: ValueKey('companion-card-${role.id}'),
                onTap: () => widget.onDetail(role),
                child: SizedBox(
                    width: 64,
                    child: Column(children: [
                      AssistantAvatar(
                          role: role.name,
                          size: 64,
                          showOnline: true,
                          onlineDotSize: 13,
                          onlineBorderWidth: 1.5,
                          closePortrait: true),
                      const SizedBox(height: 7),
                      Text(role.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BingoTypography.caption)
                    ])));
          }));

  Widget _createShortcut(
          IconData icon, String title, String subtitle, VoidCallback action) =>
      Expanded(
          child: OutlinedButton(
              onPressed: action,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  side: const BorderSide(color: BingoPalette.line),
                  shape: const StadiumBorder()),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                PearlIcon(
                    icon == Icons.groups_outlined
                        ? PearlSymbol.group
                        : PearlSymbol.personAdd,
                    size: 23,
                    color: icon == Icons.groups_outlined
                        ? BingoPalette.ink
                        : BingoPalette.primary),
                const SizedBox(width: 7),
                Flexible(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600))),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 17, color: BingoPalette.muted)
              ])));
  Widget _discover() {
    final share = _recommendations.firstOrNull;
    final gateway = widget.community;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('发现搭子', () => unawaited(_refreshRecommendation()),
          top: 30, bottom: 16, refresh: true),
      if (share != null && gateway != null)
        AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.none,
                        children: [
                          for (final child in previous)
                            // Outgoing cards keep their natural height. Forcing
                            // them into the incoming card's height overflows when
                            // the new introduction or tags use fewer lines.
                            Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(child: child)),
                          if (current != null) current,
                        ]),
                child: Material(
                    key:
                        ValueKey('recommendation-${widget.userId}-${share.id}'),
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side:
                            const BorderSide(color: BingoPalette.accentBorder)),
                    child: InkWell(
                        onTap: () => _openRecommendation(share),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                      width: 78,
                                      height: 82,
                                      child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(13),
                                          child: CompanionPortrait(
                                              share: share, gateway: gateway))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Row(children: [
                                          Expanded(
                                              child: Text(share.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: BingoTypography
                                                      .itemTitle)),
                                          CompanionLaunchButton(
                                              key: ValueKey(
                                                  'recommend-add-${share.id}'),
                                              label: _adding == share.id
                                                  ? '添加中'
                                                  : '添加',
                                              onPressed: _adding != null
                                                  ? null
                                                  : () => _install(share))
                                        ]),
                                        const SizedBox(height: 4),
                                        Wrap(
                                            spacing: 5,
                                            runSpacing: 4,
                                            children: [
                                              for (final tag in [
                                                share.roleType ?? '社区搭子',
                                                ...share.traits.take(2)
                                              ])
                                                Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 5,
                                                            vertical: 1),
                                                    decoration: BoxDecoration(
                                                        color:
                                                            BingoPalette.blush,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6)),
                                                    child: Text(tag,
                                                        style: BingoTypography
                                                            .caption
                                                            .copyWith(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: const Color(
                                                                    0xFF444444)))),
                                            ]),
                                        const SizedBox(height: 6),
                                        Text(share.introduction,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: BingoTypography.body
                                                .copyWith(fontSize: 13)),
                                      ])),
                                ]))))))
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
              padding: const EdgeInsets.symmetric(vertical: 12),
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
                                style: BingoTypography.itemTitle.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500))),
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
    return recent.take(2).map((e) => e.child).toList();
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
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: [
                    if (widget.showHeader)
                      SizedBox(
                          height: 64,
                          child: Row(children: [
                            Expanded(
                                child: Text('陪伴空间',
                                    style: CompanionLaunch.text(20,
                                        weight: FontWeight.w600))),
                            IconButton(
                                tooltip: '查找聊天',
                                onPressed: widget.onSearchChats,
                                icon:
                                    const Icon(Icons.search_rounded, size: 24))
                          ])),
                    Row(children: [
                      _createShortcut(Icons.person_add_alt_outlined, '创建搭子', '',
                          widget.onCreateRole),
                      const SizedBox(width: 10),
                      _createShortcut(Icons.groups_outlined, '创建群聊', '',
                          () => widget.onCreateGroup(''))
                    ]),
                    _heading('我的搭子', _allPartners, top: 26, bottom: 18),
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
                    _discover(),
                    InkWell(
                        onTap: widget.onMessages,
                        child: _heading('最近聊天', widget.onMessages,
                            top: 22, bottom: 8, label: '更多 ›')),
                    ..._recentChats(),
                    if (_recentChats().isEmpty)
                      TextButton(
                          onPressed: widget.onMessages,
                          child: const Text('找搭子聊聊今天吧')),
                  ]))));
}
