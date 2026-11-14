import 'package:bingo/core/design/bingo_page.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'dart:convert';
import 'dart:math';

import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_widgets.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';

class PublishCompanionPage extends StatefulWidget {
  const PublishCompanionPage(
      {required this.gateway,
      required this.roleGateway,
      this.initialRole,
      super.key});
  final CommunityGateway gateway;
  final RoleGateway roleGateway;
  final RoleOption? initialRole;
  @override
  State<PublishCompanionPage> createState() => _PublishCompanionPageState();
}

class _PublishCompanionPageState extends State<PublishCompanionPage> {
  final _introduction = TextEditingController();
  final _title = TextEditingController();
  final _tags = <String>{'治愈陪伴', '日常聊天'};
  final _form = GlobalKey<FormState>();
  String _requestId = '';
  String? _submittedContent;
  List<RoleOption>? _roles;
  RoleOption? _selected;
  bool _failed = false, _busy = false;
  @override
  void initState() {
    super.initState();
    _selected = widget.initialRole;
    _newRequest();
    _load();
  }

  void _newRequest() {
    _requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final roles = await widget.roleGateway.listRoles();
      if (mounted) {
        setState(() {
          _roles = roles;
          _selected =
              roles.where((role) => role.id == _selected?.id).firstOrNull;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _introduction.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _selected == null || _busy) return;
    FocusScope.of(context).unfocus();
    final content = jsonEncode([
      _selected!.id,
      _title.text.trim(),
      _introduction.text.trim(),
      _tags.toList()..sort()
    ]);
    if (_submittedContent != null && _submittedContent != content) {
      _newRequest();
    }
    _submittedContent = content;
    setState(() => _busy = true);
    try {
      final gateway = widget.gateway;
      final share = gateway is CommunityPublishingGateway
          ? await (gateway as CommunityPublishingGateway)
              .publishCompanionDetail(
                  roleId: _selected!.id,
                  introduction: _introduction.text.trim(),
                  title: _title.text.trim(),
                  shareTags: _tags.toList()..sort(),
                  requestId: _requestId)
          : await gateway.publishCompanion(
              roleId: _selected!.id,
              introduction: _introduction.text.trim(),
              requestId: _requestId);
      if (mounted) Navigator.pop(context, share);
    } on ApiException catch (error) {
      if (mounted) showCenterToast(context, error.message);
    } catch (_) {
      if (mounted) showCenterToast(context, '分享未完成，请检查连接后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar:
            AppBar(title: const Text('分享搭子', style: TextStyle(fontSize: 18))),
        body: _failed
            ? CommunityEmpty(
                title: '搭子暂时没加载出来',
                description: '重新连接后再试一次。',
                action: '重新加载',
                onAction: _load)
            : _roles == null
                ? const Center(child: CircularProgressIndicator())
                : Form(
                    key: _form,
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      const Text('选择要分享的搭子',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          initialValue: _selected?.id,
                          isExpanded: true,
                          decoration: InputDecoration(
                              filled: true,
                              fillColor: BingoPalette.softSurface,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none)),
                          hint: const Text('选择要分享的搭子'),
                          items: _roles!
                              .map((role) => DropdownMenuItem(
                                  value: role.id,
                                  child: Text(role.displayName,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (id) => setState(() {
                                    _selected = _roles!
                                        .firstWhere((role) => role.id == id);
                                    _newRequest();
                                  }),
                          validator: (value) =>
                              value == null ? '请先选择搭子' : null),
                      if (_selected != null) ...[
                        const SizedBox(height: 14),
                        Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                                color: BingoPalette.softSurface,
                                borderRadius: BorderRadius.circular(20)),
                            child: Row(children: [
                              AssistantAvatar(role: _selected!.name, size: 55),
                              const SizedBox(width: 13),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(_selected!.displayName,
                                        style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Text(_selected!.typeLabel,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: communityMuted)),
                                  ])),
                            ])),
                      ],
                      const SizedBox(height: 24),
                      const Text('分享标题',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: _title,
                          enabled: !_busy,
                          maxLength: 60,
                          decoration: const InputDecoration(
                              hintText: '给这份分享起个标题', counterText: '')),
                      const SizedBox(height: 24),
                      const Text('介绍与故事',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: communityInk)),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: _introduction,
                          enabled: !_busy,
                          minLines: 4,
                          maxLines: 6,
                          maxLength: 300,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '写一句介绍，让大家认识 TA 吧'
                                  : null,
                          decoration: InputDecoration(
                              hintText: 'TA 是什么样的搭子？适合一起聊些什么？',
                              hintStyle: const TextStyle(fontSize: 13),
                              filled: true,
                              fillColor: BingoPalette.softSurface,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none))),
                      const SizedBox(height: 18),
                      const Text('标签（最多选择3个）',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        for (final tag in [
                          '治愈陪伴',
                          '日常聊天',
                          '学习成长',
                          '温柔倾听',
                          '积极乐观',
                          '兴趣同好'
                        ])
                          FilterChip(
                              label: Text(tag),
                              selected: _tags.contains(tag),
                              selectedColor: BingoPalette.blush,
                              onSelected: _busy
                                  ? null
                                  : (selected) => setState(() {
                                        if (!selected) {
                                          _tags.remove(tag);
                                        } else if (_tags.length < 3) {
                                          _tags.add(tag);
                                        }
                                      }))
                      ]),
                      const SizedBox(height: 20),
                      const Text(
                          '其他人加入后会拥有独立副本，可自行编辑与再次分享。聊天记录与私人记忆不会分享，个人复刻音色会替换为系统音色。',
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.8,
                              color: communityMuted)),
                      const SizedBox(height: 14),
                      const Text('发布即表示你允许其他用户复制、修改和再次分享这些内容，请确认你有权分享。',
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.8,
                              color: communityMuted)),
                    ])),
        bottomNavigationBar: BingoActionBar(
            child: FilledButton.icon(
                onPressed: _busy || _roles == null ? null : _submit,
                style: FilledButton.styleFrom(
                    backgroundColor: communityAccent,
                    minimumSize: const Size(double.infinity, 48)),
                icon: const Icon(Icons.ios_share_rounded, size: 19),
                label: Text(_busy ? '正在分享…' : '发布分享'))),
      ));
}
