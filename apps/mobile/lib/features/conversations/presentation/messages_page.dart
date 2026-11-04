import 'package:bingo/core/design/companion_launch_ui.dart';
import 'package:bingo/core/widgets/bingo_confirm_dialog.dart';
import 'package:bingo/core/widgets/unread_badge.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/design/bingo_icon.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/stickers/sticker.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/group_avatar.dart';
import 'package:flutter/material.dart';

typedef _Chat = ({RoleOption? role, ChatGroup? group, DateTime date, bool pin});

class MessagesPage extends StatefulWidget {
  const MessagesPage(
      {required this.gateway,
      required this.groups,
      required this.onRole,
      required this.onGroup,
      required this.onCreate,
      required this.onPartners,
      this.onCreateRole,
      this.onCommunity,
      this.onGroupInfo,
      this.onUnreadChanged,
      this.showCreateAction = true,
      super.key});
  final RoleGateway gateway;
  final GroupGateway groups;
  final Future<void> Function(RoleOption) onRole;
  final Future<void> Function(ChatGroup) onGroup;
  final Future<void> Function(ChatGroup)? onGroupInfo;
  final ValueChanged<int>? onUnreadChanged;
  final VoidCallback onCreate, onPartners;
  final VoidCallback? onCreateRole, onCommunity;
  final bool showCreateAction;
  @override
  State<MessagesPage> createState() => MessagesPageState();
}

class MessagesPageState extends State<MessagesPage> {
  List<RoleOption> _roles = [];
  List<ChatGroup> _groups = [];
  bool _showSearch = false;
  bool _loading = true,
      _failed = false,
      _opening = false,
      _busy = false,
      _pinsExpanded = true;
  int _filter = 0, _loadVersion = 0;
  String _query = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _newButtonKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void showChats({bool search = false}) {
    setState(() {
      _filter = 0;
      _query = '';
      _searchController.clear();
    });
    if (search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusSearch();
      });
    }
    refresh();
  }

  void _focusSearch() {
    setState(() => _showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void onlyGroups() {
    showChats();
    setState(() => _filter = 2);
  }

  Future<void> refresh() async {
    final version = ++_loadVersion;
    try {
      final results = await Future.wait<Object>(
          [widget.gateway.listRoles(), widget.groups.listGroups()]);
      if (mounted && version == _loadVersion) {
        setState(() {
          _roles = (results[0] as List<RoleOption>)
              .where((r) => r.messageCount > 0 && !r.archived)
              .toList();
          _groups = (results[1] as List<ChatGroup>)
              .where((g) => !g.archived)
              .toList();
          _failed = false;
        });
      }
      widget.onUnreadChanged?.call(_roles
              .where((r) => !r.muted)
              .fold<int>(0, (sum, r) => sum + r.unreadCount) +
          _groups
              .where((g) => !g.muted)
              .fold<int>(0, (sum, g) => sum + g.unread));
    } catch (_) {
      if (mounted && version == _loadVersion) setState(() => _failed = true);
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _open(_Chat item) async {
    if (_opening) return;
    _opening = true;
    try {
      if (item.role != null) {
        await widget.onRole(item.role!);
      } else {
        await widget.onGroup(item.group!);
      }
      await refresh();
    } catch (_) {
      if (mounted) showCenterToast(context, '聊天暂时无法打开，请重试');
    } finally {
      _opening = false;
    }
  }

  Future<void> _apply(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await refresh();
    } catch (_) {
      if (mounted) showCenterToast(context, '操作未成功，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settings(_Chat item, {bool? pinned, bool? muted}) async {
    if (item.group != null) {
      await widget.groups.updateGroup(item.group!.id, {
        if (pinned != null) 'pinned': pinned,
        if (muted != null) 'muted': muted
      });
    } else {
      final gateway = widget.gateway;
      final id = item.role!.conversationId;
      if (gateway is! ChatInfoGateway || id == null) {
        throw StateError('Missing conversation');
      }
      await (gateway as ChatInfoGateway)
          .updateChatSettings(id, pinned: pinned, muted: muted);
    }
  }

  Future<void> _read(_Chat item) async {
    if (item.group != null) {
      await widget.groups
          .readGroup(item.group!.id, item.group!.lastMessage?.seq ?? 0);
    } else {
      final gateway = widget.gateway;
      final id = item.role!.conversationId;
      if (gateway is! RoleConversationGateway || id == null) {
        throw StateError('Missing conversation');
      }
      await (gateway as RoleConversationGateway).markConversationRead(id);
    }
  }

  Future<void> _remove(_Chat item) async {
    final yes = await showBingoConfirmDialog(context,
        title: '删除会话？',
        message: '仅从消息列表移除，保留搭子、群聊和聊天记录。产生新消息后会再次显示。',
        confirmLabel: '删除',
        icon: Icons.chat_bubble_outline_rounded,
        destructive: true);
    if (yes != true || !mounted) return;
    await _apply(() async {
      if (item.group != null) {
        await widget.groups.updateGroup(item.group!.id, {'archived': true});
      } else {
        final gateway = widget.gateway;
        final id = item.role!.conversationId;
        if (gateway is! ConversationListGateway || id == null) {
          throw StateError('Missing conversation');
        }
        await (gateway as ConversationListGateway).archiveConversation(id);
      }
    });
  }

  void _actions(_Chat item) {
    if (_busy) return;
    final muted = item.role?.muted ?? item.group!.muted;
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: BingoPalette.ice,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        builder: (sheet) {
          void run(Future<void> Function() action) {
            Navigator.pop(sheet);
            _apply(action);
          }

          return SafeArea(
              child: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 23, 18, 22),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          _avatar(item, 54),
                          const SizedBox(width: 13),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(_name(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: refInk)),
                                const SizedBox(height: 4),
                                Text(
                                    item.group == null
                                        ? '${item.role!.typeLabel} · AI 搭子'
                                        : '${item.group!.activeMembers.length}位搭子  |  群聊',
                                    style: const TextStyle(
                                        fontSize: 12, color: refMuted))
                              ])),
                          IconButton(
                              tooltip: '关闭会话操作',
                              style: IconButton.styleFrom(
                                  backgroundColor: BingoPalette.softSurface),
                              onPressed: () => Navigator.pop(sheet),
                              icon: const Icon(Icons.close_rounded,
                                  color: BingoPalette.muted))
                        ]),
                        const SizedBox(height: 18),
                        Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            clipBehavior: Clip.antiAlias,
                            child: Column(children: [
                              _actionRow(Icons.push_pin_outlined,
                                  item.pin ? '取消置顶' : '置顶聊天',
                                  onTap: () => run(() =>
                                      _settings(item, pinned: !item.pin))),
                              _actionRow(
                                  Icons.check_circle_outline_rounded, '标记为已读',
                                  onTap: () => run(() => _read(item))),
                              _actionRow(
                                  Icons.notifications_off_outlined, '消息免打扰',
                                  onTap: () =>
                                      run(() => _settings(item, muted: !muted)),
                                  trailing: Switch(
                                      value: muted,
                                      activeThumbColor: Colors.white,
                                      activeTrackColor: refMint,
                                      onChanged: (value) => run(() =>
                                          _settings(item, muted: value)))),
                              if (item.group != null)
                                _actionRow(
                                    Icons.people_outline_rounded, '查看群成员',
                                    onTap: () async {
                                  Navigator.pop(sheet);
                                  if (widget.onGroupInfo != null) {
                                    await widget.onGroupInfo!(item.group!);
                                    await refresh();
                                  } else {
                                    _members(item.group!);
                                  }
                                }),
                              _actionRow(Icons.delete_outline_rounded, '删除会话',
                                  color: const Color(0xFFF45D78),
                                  divider: false, onTap: () {
                                Navigator.pop(sheet);
                                _remove(item);
                              })
                            ]))
                      ]))));
        });
  }

  void _members(ChatGroup group) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
            for (final member in group.activeMembers)
              ListTile(
                  leading: AssistantAvatar(role: member.roleName, size: 42),
                  title: Text(member.name))
          ])));
  Widget _actionRow(IconData icon, String text,
          {required VoidCallback onTap,
          Widget? trailing,
          Color color = refInk,
          bool divider = true}) =>
      Column(children: [
        ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: Icon(icon, size: 25, color: color),
            title: Text(text, style: TextStyle(fontSize: 16, color: color)),
            trailing: trailing,
            onTap: onTap),
        if (divider)
          const Padding(
              padding: EdgeInsets.only(left: 64, right: 20),
              child: Divider(height: 1, color: BingoPalette.line))
      ]);

  @override
  Widget build(BuildContext context) {
    final items = <_Chat>[
      if (_filter != 2)
        for (final role in _roles)
          if (role.displayName.contains(_query) ||
              (role.lastMessage?.contains(_query) ?? false))
            (
              role: role,
              group: null,
              date: role.lastMessageAt ?? DateTime(2000),
              pin: role.pinned
            ),
      if (_filter != 1)
        for (final group in _groups)
          if (group.name.contains(_query) ||
              (group.lastMessage?.content.contains(_query) ?? false))
            (
              role: null,
              group: group,
              date: group.lastActivity,
              pin: group.pinned
            )
    ]..sort((a, b) => b.date.compareTo(a.date));
    final pinned = items.where((item) => item.pin).toList();
    final recent = items.where((item) => !item.pin).toList();
    return DecoratedBox(
        decoration: CompanionLaunch.background,
        child: SafeArea(
            bottom: false,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
                  child: CompanionLaunchHeader('消息',
                      horizontalPadding: 0,
                      actions: [
                        IconButton(
                            tooltip: '搜索聊天',
                            onPressed: _focusSearch,
                            icon: const Icon(Icons.search_rounded, size: 23)),
                        if (widget.showCreateAction)
                          IconButton(
                              key: _newButtonKey,
                              tooltip: '新建',
                              onPressed: _newMenu,
                              icon: const Icon(Icons.add_circle_outline_rounded,
                                  size: 26)),
                      ])),
              if (_showSearch || _query.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                    child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        onChanged: (value) =>
                            setState(() => _query = value.trim()),
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                            hintText: '搜索搭子或聊天记录',
                            prefixIconConstraints:
                                BoxConstraints(minWidth: 40, minHeight: 40),
                            hintStyle: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: BingoPalette.muted),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            prefixIcon: Icon(Icons.search_rounded, size: 20)))),
              Padding(
                  padding: EdgeInsets.zero,
                  child: CompanionLaunchTabs(
                      tabs: const [
                        (value: 0, label: '全部'),
                        (value: 1, label: '单聊'),
                        (value: 2, label: '群聊')
                      ],
                      selected: _filter,
                      onSelected: (value) => setState(() => _filter = value))),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                  child: RefreshIndicator(
                      onRefresh: refresh,
                      child: ListView(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            if (_loading)
                              const Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Center(
                                      child: CircularProgressIndicator()))
                            else if (_failed)
                              TextButton(
                                  onPressed: refresh,
                                  child: const Text('加载失败，点击重试'))
                            else if (items.isEmpty)
                              Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(children: [
                                    Text(
                                        _query.isEmpty
                                            ? '还没有最近的对话'
                                            : '没有找到相关聊天',
                                        style:
                                            const TextStyle(color: refMuted)),
                                    TextButton(
                                        onPressed: widget.onPartners,
                                        child: const Text('找搭子聊聊')),
                                  ]))
                            else ...[
                              if (pinned.isNotEmpty) ...[
                                InkWell(
                                    onTap: () => setState(
                                        () => _pinsExpanded = !_pinsExpanded),
                                    child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            4, 0, 4, 10),
                                        child: Row(children: [
                                          const Expanded(
                                              child: Text('置顶聊天',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          BingoPalette.muted))),
                                          Icon(
                                              _pinsExpanded
                                                  ? Icons.expand_less
                                                  : Icons.expand_more,
                                              size: 16,
                                              color: BingoPalette.muted),
                                        ]))),
                                if (_pinsExpanded) _listGroup(pinned),
                              ],
                              if (recent.isNotEmpty) ...[
                                if (pinned.isNotEmpty)
                                  const SizedBox(height: 8),
                                _listGroup(recent),
                              ],
                            ],
                          ]))),
            ])));
  }

  Widget _listGroup(List<_Chat> items) => Column(children: [
        for (var i = 0; i < items.length; i++)
          _tile(items[i], divider: i < items.length - 1)
      ]);

  Future<void> _newMenu() async {
    final box = _newButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final media = MediaQuery.of(context);
    final top = (box.localToGlobal(Offset.zero).dy + box.size.height + 8)
        .clamp(media.padding.top + 8, media.size.height - 100)
        .toDouble();
    final value = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭新建菜单',
        barrierColor: const Color(0x660F2723),
        transitionDuration: const Duration(milliseconds: 160),
        transitionBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
                scale: Tween<double>(begin: .96, end: 1).animate(animation),
                alignment: Alignment.topRight,
                child: child)),
        pageBuilder: (_, __, ___) => Stack(children: [
              Positioned(
                  top: top,
                  right: 18,
                  width: (media.size.width - 36).clamp(0, 300).toDouble(),
                  child: Material(
                      color: BingoPalette.surface,
                      elevation: 8,
                      shadowColor: const Color(0x2523463B),
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight: media.size.height -
                                  top -
                                  media.padding.bottom -
                                  12),
                          child: SingleChildScrollView(
                              child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _newItem(
                                            'group',
                                            '创建群聊',
                                            '和多个 AI 搭子一起聊天',
                                            Icons.people_outline_rounded),
                                        const Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 18),
                                            child: Divider(
                                                height: 1,
                                                color: BingoPalette.line)),
                                        _newItem('role', '创建搭子', '定制你的专属 AI 搭子',
                                            Icons.person_add_alt_1_outlined),
                                        const Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 18),
                                            child: Divider(
                                                height: 1,
                                                color: BingoPalette.line)),
                                        _newItem('community', '从社区添加',
                                            '发现更多有趣的搭子', Icons.explore_outlined)
                                      ]))))))
            ]));
    if (!mounted) return;
    switch (value) {
      case 'group':
        widget.onCreate();
      case 'role':
        (widget.onCreateRole ?? widget.onPartners)();
      case 'community':
        (widget.onCommunity ?? widget.onPartners)();
    }
  }

  Widget _newItem(String value, String title, String subtitle, IconData icon) =>
      Builder(
          builder: (context) => InkWell(
              onTap: () => Navigator.pop(context, value),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Container(
                        width: 45,
                        height: 45,
                        decoration: BoxDecoration(
                            color: BingoPalette.blush,
                            borderRadius: BorderRadius.circular(15)),
                        child: Center(
                            child: value == 'group'
                                ? const BingoIcon(BingoSymbol.group,
                                    size: 28, color: BingoPalette.primary)
                                : Icon(icon,
                                    size: 28, color: BingoPalette.primary))),
                    const SizedBox(width: 13),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: refInk)),
                          const SizedBox(height: 5),
                          Text(subtitle,
                              style: const TextStyle(
                                  fontSize: 12, color: refMuted))
                        ]))
                  ]))));
  String _name(_Chat item) => item.role?.displayName ?? item.group!.name;
  Widget _avatar(_Chat item, double size) => item.role != null
      ? AssistantAvatar(role: item.role!.name, size: size)
      : GroupAvatar(members: item.group!.activeMembers, size: size);
  Widget _tile(_Chat item, {bool divider = true}) {
    final role = item.role, group = item.group;
    final unread = role?.unreadCount ?? group!.unread;
    final muted = role?.muted ?? group!.muted;
    final preview = role != null
        ? role.lastMessage ?? '和搭子打个招呼吧'
        : group!.lastMessage == null
            ? '和搭子们打个招呼吧'
            : '${group.senderNameFor(group.lastMessage!)}：${ChatSticker.preview(group.lastMessage!.content)}';
    return Material(
        key: ValueKey('chat-${role?.id ?? group!.id}'),
        color: Colors.white,
        child: InkWell(
            onTap: () => _open(item),
            onLongPress: () => _actions(item),
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    border: divider
                        ? const Border(
                            bottom: BorderSide(color: BingoPalette.line))
                        : null),
                child: Row(children: [
                  _avatar(item, CompanionLaunch.compact(context) ? 59 : 64),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Flexible(
                              child: Text(_name(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: refInk))),
                          if (group != null) ...[
                            const SizedBox(width: 6),
                            const BingoIcon(BingoSymbol.group,
                                size: 17, color: BingoPalette.muted)
                          ]
                        ]),
                        const SizedBox(height: 6),
                        Text(ChatSticker.preview(preview),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: BingoPalette.muted))
                      ])),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_time(item.date),
                        style: const TextStyle(
                            fontSize: 11, color: BingoPalette.muted)),
                    if (unread > 0) ...[
                      const SizedBox(height: 7),
                      UnreadBadge(count: unread)
                    ] else if (item.pin || muted) ...[
                      const SizedBox(height: 7),
                      Icon(
                          muted
                              ? Icons.notifications_off_outlined
                              : Icons.push_pin_outlined,
                          size: 13,
                          color: BingoPalette.muted)
                    ],
                    if ((group?.unreadMentions ?? 0) > 0)
                      const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Text('@我',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFFFF4D4F))))
                  ])
                ]))));
  }
}

String _time(DateTime date) {
  final local = date.toUtc().add(const Duration(hours: 8));
  final now = DateTime.now().toUtc().add(const Duration(hours: 8));
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (today.difference(day).inDays == 1) return '昨天';
  return local.year == now.year
      ? '${local.month}/${local.day}'
      : '${local.year}/${local.month}/${local.day}';
}
