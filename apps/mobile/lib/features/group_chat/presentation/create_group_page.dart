import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/group_avatar.dart';
import 'package:flutter/material.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage(
      {required this.gateway,
      required this.roles,
      this.initialName = '快乐小窝',
      this.initialRoleIds,
      super.key});
  final GroupGateway gateway;
  final RoleGateway roles;
  final String initialName;
  final List<String>? initialRoleIds;
  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  late final _name = TextEditingController(text: widget.initialName);
  final _selected = <String>{};
  List<RoleOption>? _roles;
  bool _failed = false, _saving = false;
  String _cover = 'coffee';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final roles = await widget.roles.listRoles();
      if (mounted) {
        setState(() {
          _roles = roles;
          _selected.addAll(
              widget.initialRoleIds ?? roles.take(4).map((role) => role.id));
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _selected.length < 2) {
      showCenterToast(context, '请填写名称并选择至少两位搭子');
      return;
    }
    setState(() => _saving = true);
    try {
      final group = await widget.gateway.createGroup({
        'name': _name.text.trim(),
        'role_ids': _selected.toList(),
        'description': '一起分享生活、聊聊工作，记录每一个温暖的瞬间。',
        'cover': _cover,
        'allow_ai_to_ai': true,
        'mentions_enabled': true,
        'proactive_enabled': true
      });
      if (mounted) Navigator.pop(context, group);
    } on ApiException catch (error) {
      if (mounted) showCenterToast(context, error.message);
    } catch (_) {
      if (mounted) showCenterToast(context, '群聊创建失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Scaffold(
          backgroundColor: BingoPalette.pageTop,
          appBar: AppBar(title: const Text('创建群聊'), centerTitle: true),
          body: ReferenceBackdrop(
              showHeaderArt: false,
              child: _roles == null
                  ? Center(
                      child: _failed
                          ? TextButton(
                              onPressed: _load, child: const Text('加载失败，点击重试'))
                          : const CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                          Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: BingoPalette.blush,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Row(children: [
                                GroupAvatar.roles(
                                    _roles!
                                        .where((r) => _selected.contains(r.id))
                                        .map((r) => r.name)
                                        .toList(),
                                    cover: _cover,
                                    size: 100),
                                const Spacer(),
                                PopupMenuButton<String>(
                                    tooltip: '更换封面',
                                    initialValue: _cover,
                                    onSelected: (v) =>
                                        setState(() => _cover = v),
                                    itemBuilder: (_) => [
                                          for (final (value, text) in [
                                            ('coffee', '温暖咖啡'),
                                            ('night', '深夜树洞'),
                                            ('garden', '搭子小窝')
                                          ])
                                            PopupMenuItem(
                                                value: value, child: Text(text))
                                        ],
                                    child: const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: Row(children: [
                                          Icon(Icons.image_outlined, size: 19),
                                          SizedBox(width: 6),
                                          Text('更换封面',
                                              style: TextStyle(fontSize: 12)),
                                          Icon(Icons.chevron_right_rounded,
                                              size: 18)
                                        ])))
                              ])),
                          const SizedBox(height: 22),
                          const Text('群聊名称',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          TextField(
                              controller: _name,
                              maxLength: 20,
                              enabled: !_saving,
                              decoration: const InputDecoration(
                                  hintText: '给群聊起一个温暖的名字')),
                          const SizedBox(height: 12),
                          Text('选择搭子 ${_selected.length}/8',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 7),
                          const Text('最多可选择8位搭子',
                              style: TextStyle(fontSize: 11, color: refMuted)),
                          const SizedBox(height: 12),
                          for (final role in _roles!)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 7),
                                child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(17),
                                    child: CheckboxListTile(
                                        value: _selected.contains(role.id),
                                        activeColor: refMint,
                                        secondary: AssistantAvatar(
                                            role: role.name, size: 50),
                                        title: Text(role.displayName,
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800)),
                                        subtitle: Text(role.cardDescription,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11, color: refMuted)),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(17)),
                                        onChanged: _saving
                                            ? null
                                            : (selected) => setState(() {
                                                  if (selected != true) {
                                                    _selected.remove(role.id);
                                                  } else if (_selected.length <
                                                      8) {
                                                    _selected.add(role.id);
                                                  } else {
                                                    showCenterToast(
                                                        context, '最多选择 8 位搭子');
                                                  }
                                                })))),
                        ])),
          bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: ReferenceButton(_saving ? '正在创建…' : '创建群聊',
                      onPressed: _saving ? null : _save)))));
}
