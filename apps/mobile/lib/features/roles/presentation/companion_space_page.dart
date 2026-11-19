import 'package:bingo/core/design/home_artwork_icon.dart';
import 'package:bingo/core/widgets/recent_chat_feedback.dart';
import 'package:bingo/core/design/companion_launch_ui.dart';
import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';
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
      required this.onSearchChats,
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
  final VoidCallback onAllGroups, onCommunity, onMessages, onSearchChats;
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
                style: BingoTypography.sectionTitle.copyWith(fontSize: 17)),
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
                      const TextStyle(fontSize: 12, color: BingoPalette.muted)),
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
        child: OutlinedButton(
          onPressed: action,
          style: OutlinedButton.styleFrom(
            backgroundColor: background,
            foregroundColor: BingoPalette.ink,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            side: const BorderSide(color: BingoPalette.line),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
          child: Row(children: [
            HomeArtworkIcon(icon, size: 19, color: BingoPalette.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                            BingoTypography.itemTitle.copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: BingoTypography.caption.copyWith(fontSize: 10)),
                  ]),
            ),
            const HomeArtworkIcon(HomeArtwork.next,
                size: 15, color: BingoPalette.ink),
          ]),
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
          bool group = false}) =>
      RecentChatFeedback(
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
  Widget build(BuildContext context) {
    final roles = _roles;
    final recent = _recentChats();
    return DecoratedBox(
      decoration: CompanionLaunch.background,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
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
              const SizedBox(height: 10),
              const Divider(height: 1, color: BingoPalette.line),
              _heading('每个人，都可以成为你的搭子', null, top: 14, bottom: 10),
              IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _homeShortcut(HomeArtwork.plus, '创建搭子', '创建专属的 AI 搭子',
                          const Color(0xFFF8F8FA), widget.onCreateRole),
                      const SizedBox(width: 9),
                      _homeShortcut(HomeArtwork.compass, '社区推荐', '发现更多有趣的搭子',
                          const Color(0xFFFFF1F6), widget.onCommunity),
                    ]),
              ),
              const SizedBox(height: 17),
              const Divider(height: 1, color: BingoPalette.line),
              Row(children: [
                Expanded(
                    child: InkWell(
                        onTap: widget.onMessages,
                        child: _heading('最近聊天', widget.onMessages,
                            top: 12, bottom: 2, label: '全部聊天 ›'))),
                IconButton(
                    tooltip: '查找聊天',
                    onPressed: widget.onSearchChats,
                    icon: const Icon(Icons.search_rounded, size: 19)),
              ]),
              ...recent,
              if (recent.isEmpty && roles != null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('最近的对话会显示在这里', style: BingoTypography.caption),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
