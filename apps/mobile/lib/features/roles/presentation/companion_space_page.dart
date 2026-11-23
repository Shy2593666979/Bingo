import 'package:bingo/core/design/home_artwork_icon.dart';
import 'package:bingo/core/widgets/recent_chat_feedback.dart';
import 'package:bingo/core/design/companion_launch_ui.dart';
import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/theme/home_palette.dart';
import 'package:bingo/core/design/bingo_icon.dart';
import 'package:bingo/core/widgets/unread_badge.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/roles/data/local_role_order_store.dart';
import 'package:bingo/features/roles/presentation/home_companion_carousel.dart';
import 'package:bingo/features/roles/presentation/home_greeting.dart';
import 'package:bingo/features/stickers/sticker.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
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
      this.onReady,
      this.showHeader = true,
      this.nickname,
      this.active = true,
      super.key});
  final RoleGateway gateway;
  final GroupGateway groups;
  final String userId;
  final Future<void> Function(RoleOption) onChat, onDetail;
  final Future<void> Function(ChatGroup) onOpenGroup;
  final Future<void> Function(String) onCreateGroup;
  final Future<void> Function() onCreateRole;
  final VoidCallback? onReady;
  final VoidCallback onAllGroups, onCommunity, onMessages;
  final bool showHeader, active;
  final String? nickname;
  @override
  State<CompanionSpacePage> createState() => CompanionSpacePageState();
}

class CompanionSpacePageState extends State<CompanionSpacePage> {
  bool _startupReported = false;
  List<RoleOption>? _roles;
  List<ChatGroup> _groups = [];
  bool _failed = false, _loading = false;
  int _version = 0;
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
      _loading = false;
      _roles = null;
      _groups = [];
      unawaited(refresh());
    }
  }

  Future<void> createCompanion() => widget.onCreateRole();
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    final version = ++_version;
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
      });
    } catch (_) {
      if (mounted && version == _version) setState(() => _failed = true);
    } finally {
      if (version == _version) _loading = false;
      if (!_startupReported && widget.onReady != null) {
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
    ];
    await Future.wait(jobs)
        .timeout(const Duration(seconds: 5), onTimeout: () => []);
  }

  Widget _heading(String text, VoidCallback? more,
          {String label = '全部 ›', double top = 16, double bottom = 8}) =>
      Padding(
        padding: EdgeInsets.only(top: top, bottom: bottom),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: BingoTypography.sectionTitle
                    .copyWith(fontSize: 17, color: HomePalette.ink)),
          ),
          if (more != null)
            TextButton(
              onPressed: more,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 30),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: HomePalette.muted)),
            ),
        ]),
      );

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
  Widget _homeShortcut(HomeArtwork icon, String title, String subtitle,
          Color background, VoidCallback action) =>
      Expanded(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: action,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF1EBF0)),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x09000000),
                      blurRadius: 12,
                      offset: Offset(0, 4)),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: HomeArtworkIcon(icon,
                        size: 18, color: HomePalette.accent),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BingoTypography.itemTitle.copyWith(
                                fontSize: 14.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BingoTypography.caption.copyWith(
                                fontSize: 11, color: HomePalette.muted)),
                      ]),
                ),
              ]),
            ),
          ),
        ),
      );

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
          bool group = false,
          bool showDivider = true}) =>
      RecentChatFeedback(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  border: showDivider
                      ? const Border(
                          bottom: BorderSide(color: Color(0xFFF3EEF2)))
                      : null),
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
                                    fontWeight: FontWeight.w600))),
                        if (group) ...[
                          const SizedBox(width: 6),
                          const BingoIcon(BingoSymbol.group,
                              size: 16, color: BingoPalette.muted)
                        ]
                      ]),
                      const SizedBox(height: 3),
                      Text(ChatSticker.preview(preview),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, color: CompanionLaunch.muted))
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
    final items = <({
      DateTime date,
      Widget avatar,
      String name,
      String preview,
      int unread,
      bool group,
      VoidCallback onTap,
    })>[];
    for (final g
        in _groups.where((g) => !g.archived && g.lastMessage != null)) {
      items.add((
        date: g.lastActivity,
        avatar: GroupAvatar(members: g.activeMembers, size: 48),
        name: g.name,
        preview:
            '${g.senderNameFor(g.lastMessage!)}：${g.lastMessage!.content}',
        unread: g.unread,
        group: true,
        onTap: () => widget.onOpenGroup(g),
      ));
    }
    for (final r in (_roles ?? <RoleOption>[])
        .where((r) => r.messageCount > 0 && !r.archived)) {
      items.add((
        date: r.lastMessageAt ?? DateTime(2000),
        avatar: AssistantAvatar(role: r.name, size: 48),
        name: r.displayName,
        preview: r.lastMessage ?? '和搭子聊聊吧',
        unread: r.unreadCount,
        group: false,
        onTap: () => widget.onChat(r),
      ));
    }
    items.sort((a, b) => b.date.compareTo(a.date));
    final top = items.take(2).toList();
    return [
      for (var i = 0; i < top.length; i++)
        _recentRow(
          avatar: top[i].avatar,
          name: top[i].name,
          preview: top[i].preview,
          date: top[i].date,
          unread: top[i].unread,
          group: top[i].group,
          showDivider: i < top.length - 1,
          onTap: top[i].onTap,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final roles = _roles;
    final recent = _recentChats();
    return ColoredBox(
      color: const Color(0xFFFAF7F9),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              if (widget.showHeader) HomeGreeting(nickname: widget.nickname),
              if (roles == null && !_failed)
                const Center(child: CircularProgressIndicator())
              else if (roles == null)
                TextButton(onPressed: refresh, child: const Text('加载失败，点击重试'))
              else if (roles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: FilledButton(
                      onPressed: widget.onCreateRole,
                      child: const Text('创建自己的第一位搭子')),
                )
              else
                HomeCompanionCarousel(
                  key: ValueKey(
                      (widget.userId, roles.map((r) => r.id).join('|'))),
                  roles: roles,
                  active: widget.active,
                  onChat: widget.onChat,
                  onDetail: widget.onDetail,
                  onAll: _allPartners,
                ),
              _heading('每个人，都可以成为你的搭子', null, top: 18, bottom: 10),
              IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _homeShortcut(HomeArtwork.plus, '创建搭子', '定制专属 AI 搭子',
                          const Color(0xFFFDECF2), widget.onCreateRole),
                      const SizedBox(width: 10),
                      _homeShortcut(HomeArtwork.compass, '社区推荐', '发现更多有趣搭子',
                          const Color(0xFFF3EEFD), widget.onCommunity),
                    ]),
              ),
              InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: widget.onMessages,
                  child: _heading('最近聊天', widget.onMessages,
                      top: 18, bottom: 10, label: '全部聊天 ›')),
              if (recent.isNotEmpty)
                Container(
                  clipBehavior: Clip.antiAlias,
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
                  child: Column(children: recent),
                ),
              if (recent.isEmpty && roles != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFF1EBF0)),
                  ),
                  child: const Text('最近的对话会显示在这里',
                      style: BingoTypography.caption),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
