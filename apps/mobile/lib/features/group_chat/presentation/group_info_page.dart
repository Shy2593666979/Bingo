import 'package:bingo/core/design/bingo_surface.dart';
import 'package:bingo/core/widgets/bingo_confirm_dialog.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/design/h2_widgets.dart';
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/core/appearance/appearance_page.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage(
      {required this.group,
      required this.gateway,
      required this.roles,
      this.userAvatarData,
      this.appearanceStore,
      super.key});
  final ChatGroup group;
  final GroupGateway gateway;
  final RoleGateway roles;
  final String? userAvatarData;
  final AppearanceStore? appearanceStore;
  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late ChatGroup _group = widget.group;
  bool _saving = false;
  Future<void> _change(Map<String, dynamic> data) async {
    setState(() => _saving = true);
    try {
      final group = await widget.gateway.updateGroup(_group.id, data);
      if (mounted) setState(() => _group = group);
    } catch (_) {
      if (mounted) showCenterToast(context, '设置未能保存，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _rename() async {
    final edit = TextEditingController(text: _group.name);
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('修改群聊名称'),
                content: TextField(controller: edit, maxLength: 20),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, edit.text.trim()),
                      child: const Text('保存'))
                ]));
    if (value != null && value.isNotEmpty) await _change({'name': value});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    edit.dispose();
  }

  Future<void> _add() async {
    try {
      final roles = await widget.roles.listRoles();
      if (!mounted) return;
      final current = _group.activeMembers.map((person) => person.id).toSet();
      final choices =
          roles.where((role) => !current.contains(role.id)).toList();
      final role = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                const ListTile(title: Text('添加搭子到群聊')),
                if (choices.isEmpty) const ListTile(title: Text('所有搭子都已经在群里了')),
                for (final person in choices)
                  ListTile(
                      leading: AssistantAvatar(role: person.name, size: 36),
                      title: Text(person.displayName),
                      onTap: () => Navigator.pop(context, person.id))
              ])));
      if (role != null) {
        final group = await widget.gateway.addGroupMembers(_group.id, [role]);
        if (mounted) setState(() => _group = group);
      }
    } catch (_) {
      if (mounted) showCenterToast(context, '添加失败，请确认群成员未超过 8 位');
    }
  }

  Future<void> _remove(GroupPerson person) async {
    final yes = await showBingoConfirmDialog(context,
        title: '将${person.name}移出群聊？',
        message: '群内历史发言会保留，搭子的单聊不受影响。',
        confirmLabel: '移出',
        icon: Icons.person_remove_outlined,
        destructive: true);
    if (yes == true) {
      try {
        final group =
            await widget.gateway.removeGroupMember(_group.id, person.id);
        if (mounted) setState(() => _group = group);
      } catch (_) {
        if (mounted) showCenterToast(context, '移出失败，请重试');
      }
    }
  }

  Future<void> _clear({bool destroy = false}) async {
    final yes = await showBingoConfirmDialog(context,
        title: destroy ? '解散群聊？' : '清空群聊记录？',
        message: destroy ? '群聊和群记忆将被删除，搭子与单聊仍会保留。' : '将停止当前回复，清空群消息和群记忆，无法恢复。',
        confirmLabel: '确认',
        icon: destroy
            ? Icons.group_remove_outlined
            : Icons.delete_outline_rounded,
        destructive: true);
    if (yes != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.gateway.clearGroup(_group.id, destroy: destroy);
      if (mounted) {
        if (destroy) {
          Navigator.pop(context, true);
        } else {
          showCenterToast(context, '群聊记录已清空');
        }
      }
    } catch (_) {
      if (mounted) showCenterToast(context, '操作失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _appearance(int tab) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => AppearancePage(
              store: widget.appearanceStore!,
              roleId: 'group:${_group.id}',
              partnerName: _group.name,
              initialTab: tab)));

  Widget _row(String title,
          {VoidCallback? onTap, Widget? trailing, String? subtitle}) =>
      ListTile(
          title: Text(title, style: const TextStyle(fontSize: 15)),
          subtitle: subtitle == null
              ? null
              : Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: refMuted)),
          trailing: trailing ??
              const Icon(Icons.chevron_right_rounded, color: refMuted),
          onTap: onTap);
  Widget _switch(String title, bool value, String key, {String? subtitle}) =>
      _row(title,
          subtitle: subtitle,
          trailing: CupertinoSwitch(
              value: value,
              activeTrackColor: refMint,
              onChanged: _saving ? null : (value) => _change({key: value})));
  double get _memberSize =>
      ((MediaQuery.sizeOf(context).width - 100) / 6).clamp(30.0, 60.0);
  Widget _member(Widget avatar, String name) => SizedBox(
      width: _memberSize,
      child: Column(children: [
        SizedBox.square(
            dimension: _memberSize, child: FittedBox(child: avatar)),
        const SizedBox(height: 7),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: refMuted))
      ]));
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Scaffold(
          backgroundColor: BingoPalette.ice,
          appBar: AppBar(title: const Text('群聊信息'), centerTitle: true),
          body: AbsorbPointer(
              absorbing: _saving,
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    BingoSurface(
                        child: Column(children: [
                      Wrap(spacing: 8, runSpacing: 14, children: [
                        for (final person in _group.activeMembers)
                          InkWell(
                              onTap: () => _remove(person),
                              child: _member(
                                  AssistantAvatar(
                                      role: person.roleName, size: 49),
                                  person.name)),
                        _member(
                            UserAvatar(
                                size: 49,
                                avatarData: widget.userAvatarData,
                                username: _group.humanName),
                            '我'),
                        if (_group.activeMembers.length < 8)
                          _member(
                              SizedBox(
                                  width: 49,
                                  height: 49,
                                  child: IconButton.outlined(
                                      tooltip: '添加搭子',
                                      onPressed: _add,
                                      icon: const Icon(Icons.add_rounded,
                                          color: refMuted))),
                              '添加')
                      ]),
                      const SizedBox(height: 17),
                      Text('${_group.activeMembers.length}位搭子 · 最多8位搭子',
                          style: const TextStyle(fontSize: 11, color: refMuted))
                    ])),
                    const SizedBox(height: 13),
                    H2Group(children: [
                      _row('群聊名称',
                          onTap: _rename,
                          trailing: SizedBox(
                              width: 160,
                              child: Text(_group.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: refMuted)))),
                      _row('查找聊天记录',
                          onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                  builder: (_) => _GroupSearch(
                                      group: _group, gateway: widget.gateway))))
                    ]),
                    const SizedBox(height: 13),
                    H2Group(children: [
                      _switch('置顶聊天', _group.pinned, 'pinned'),
                      _switch('消息免打扰', _group.muted, 'muted'),
                      _switch('开启声音', _group.readAloud, 'read_aloud',
                          subtitle: '自动播放新回复'),
                      _switch(
                          '允许 AI 自由接话', _group.allowAiToAi, 'allow_ai_to_ai')
                    ]),
                    const SizedBox(height: 13),
                    H2Group(children: [
                      if (widget.appearanceStore != null)
                        _row('聊天外观', onTap: () => _appearance(2)),
                      _row('清空聊天记录', onTap: _clear)
                    ]),
                    const SizedBox(height: 13),
                    H2Group(children: [
                      ExpansionTile(
                          title: const Text('更多设置',
                              style: TextStyle(fontSize: 14, color: refMuted)),
                          children: [
                            _switch('支持 @ 指定回复', _group.mentionsEnabled,
                                'mentions_enabled'),
                            _switch('主动开启话题', _group.proactiveEnabled,
                                'proactive_enabled'),
                            _row(_group.archived ? '会话已暂停，发消息后继续' : '暂停会话',
                                onTap: _group.archived
                                    ? null
                                    : () => _change({'archived': true}))
                          ])
                    ]),
                    const SizedBox(height: 14),
                    TextButton(
                        onPressed: () => _clear(destroy: true),
                        style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFFFFEAF0),
                            foregroundColor: BingoPalette.rose,
                            minimumSize: const Size(double.infinity, 48)),
                        child: const Text('解散群聊'))
                  ]))));
}

class _GroupSearch extends StatefulWidget {
  const _GroupSearch({required this.group, required this.gateway});
  final ChatGroup group;
  final GroupGateway gateway;
  @override
  State<_GroupSearch> createState() => _GroupSearchState();
}

class _GroupSearchState extends State<_GroupSearch> {
  final _query = TextEditingController();
  final _messages = <GroupChatMessage>[];
  bool _loading = true, _failed = false, _more = false;
  int? _before;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items =
          await widget.gateway.groupMessages(widget.group.id, before: _before);
      if (mounted) {
        setState(() {
          final ids = _messages.map((m) => m.id).toSet();
          _messages.addAll(items.where((m) => ids.add(m.id)));
          _messages.sort((a, b) => b.seq.compareTo(a.seq));
          _more = items.isNotEmpty;
          if (items.isNotEmpty) {
            _before = items.map((m) => m.seq).reduce((a, b) => a < b ? a : b);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    return Scaffold(
        appBar: AppBar(title: const Text('查找聊天记录')),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      hintText: '搜索群聊内容或成员',
                      prefixIcon: Icon(Icons.search_rounded)))),
          Expanded(
              child: ListView(children: [
            for (final m in _messages.where((m) =>
                ('${m.name} ${m.content}').toLowerCase().contains(query)))
              ListTile(
                  title: Text(m.name,
                      style: const TextStyle(fontSize: 13, color: refMint)),
                  subtitle: Text(m.content,
                      maxLines: 4, overflow: TextOverflow.ellipsis)),
            if (!_loading && !_failed && _messages.isEmpty)
              const ListTile(title: Text('还没有聊天记录')),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_failed)
              TextButton(onPressed: _load, child: const Text('加载失败，重试')),
            if (!_loading && _more)
              TextButton(onPressed: _load, child: const Text('加载更早的记录'))
          ]))
        ]));
  }
}
