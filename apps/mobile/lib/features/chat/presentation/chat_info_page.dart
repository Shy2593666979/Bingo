import 'package:bingo/core/widgets/bingo_confirm_dialog.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'dart:async';

import 'package:bingo/core/appearance/appearance_page.dart';
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/companion_records_page.dart';
import 'package:bingo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _pageColor = BingoPalette.ice;
const _ink = BingoPalette.ink;

class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage(
      {required this.controller,
      required this.partnerName,
      required this.partnerRole,
      this.gateway,
      this.appearanceStore,
      this.roleId,
      this.onCall,
      this.imageUrlBuilder,
      this.imageAccessToken,
      super.key});
  final ChatController controller;
  final String partnerName;
  final String? partnerRole, roleId;
  final ChatInfoGateway? gateway;
  final AppearanceStore? appearanceStore;
  final VoidCallback? onCall;
  final String Function(String)? imageUrlBuilder;
  final String? imageAccessToken;

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  ChatSettings _settings = const ChatSettings();
  bool _loading = true, _saving = false, _failed = false, _clearing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final id = widget.controller.conversationId;
      if (widget.gateway != null && id != null) {
        final settings = await widget.gateway!.getChatSettings(id);
        if (mounted) setState(() => _settings = settings);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({bool? muted, bool? pinned}) async {
    final id = widget.controller.conversationId;
    if (id == null || widget.gateway == null) return;
    setState(() => _saving = true);
    try {
      final settings = await widget.gateway!
          .updateChatSettings(id, muted: muted, pinned: pinned);
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      if (mounted) showCenterToast(context, '设置未能保存，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _appearance(int tab) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => AppearancePage(
              store: widget.appearanceStore!,
              roleId: widget.roleId,
              partnerName: widget.partnerName,
              initialTab: tab)));

  Future<void> _clear() async {
    if (widget.controller.isBusy) {
      showCenterToast(context, '请等当前回复结束后再清空');
      return;
    }
    final confirmed = await showBingoConfirmDialog(context,
        title: '清空聊天记录？',
        message: '将清空与${widget.partnerName}的聊天消息，清空后无法恢复。\n已保存的陪伴记录和记忆会保留。',
        confirmLabel: '清空',
        icon: Icons.delete_outline_rounded,
        destructive: true);
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await widget.controller.clearHistory(widget.gateway!);
      if (mounted) showCenterToast(context, '聊天记录已清空');
    } on ApiException catch (error) {
      if (mounted) showCenterToast(context, error.message);
    } catch (_) {
      if (mounted) showCenterToast(context, '清空失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.appearanceStore == null
        ? const Color(0xFF4D846B)
        : ChatSkin.find(widget.appearanceStore!.effective(widget.roleId).bubble)
            .accent;
    final canSave = !_loading &&
        !_failed &&
        !_saving &&
        widget.gateway != null &&
        widget.controller.conversationId != null;
    return PopScope(
        canPop: !_clearing && !_saving,
        child: Scaffold(
          backgroundColor: _pageColor,
          appBar: _appBar('聊天信息'),
          body: AbsorbPointer(
              absorbing: _clearing,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.fromLTRB(22, 25, 22, 20),
                    alignment: Alignment.centerLeft,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AssistantAvatar(role: widget.partnerRole, size: 55),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(widget.partnerName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF929C96)))),
                    ])),
                const SizedBox(height: 12),
                _group([
                  _row('查找聊天记录',
                      onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                              builder: (_) => ChatSearchPage(info: widget)))),
                  if (widget.onCall != null) _row('语音通话', onTap: widget.onCall)
                ]),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_failed)
                  TextButton(
                      onPressed: _load, child: const Text('设置读取失败，点击重试')),
                _group([
                  _toggle('消息免打扰', _settings.muted,
                      canSave ? (value) => _save(muted: value) : null, accent),
                  _toggle('置顶聊天', _settings.pinned,
                      canSave ? (value) => _save(pinned: value) : null, accent),
                  ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, child) => _toggle(
                          '开启声音',
                          widget.controller.readAloudEnabled,
                          (value) => widget.controller.setReadAloud(value),
                          accent)),
                ]),
                if (widget.appearanceStore != null)
                  _group([
                    _row('聊天外观',
                        icon: Icons.palette_outlined,
                        onTap: () => _appearance(2)),
                  ]),
                if (widget.controller.userId != null)
                  _group([
                    _row('陪伴记录',
                        onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                                builder: (_) => CompanionRecordsPage(
                                    userId: widget.controller.userId!,
                                    conversationId:
                                        widget.controller.conversationId)))),
                  ]),
                if (widget.gateway != null)
                  _group([
                    _row(_clearing ? '正在清空…' : '清空聊天记录',
                        onTap: _clearing ? null : _clear),
                  ]),
              ])),
        ));
  }
}

AppBar _appBar(String title) => AppBar(
    backgroundColor: _pageColor,
    foregroundColor: _ink,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    title: Text(title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    leading: Builder(
        builder: (context) => IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.chevron_left_rounded, size: 28))));

Widget _group(List<Widget> rows) => Container(
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14)),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.only(left: 20),
    child: Column(children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0)
          const Divider(height: 1, thickness: .5, color: Color(0xFFE8ECE9)),
        rows[i],
      ]
    ]));

Widget _row(String title,
        {VoidCallback? onTap, Widget? trailing, IconData? icon}) =>
    Material(
        color: Colors.white,
        child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 57),
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
                    child: Row(children: [
                      if (icon != null) ...[
                        Icon(icon, size: 23, color: _ink),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                          child: Text(title,
                              style:
                                  const TextStyle(fontSize: 16, color: _ink))),
                      const SizedBox(width: 12),
                      trailing ??
                          const Icon(Icons.chevron_right_rounded,
                              size: 24, color: Color(0xFFA7AFAA)),
                    ])))));

Widget _toggle(String title, bool value, ValueChanged<bool>? onChanged,
        Color accent) =>
    _row(title,
        onTap: onChanged == null ? null : () => onChanged(!value),
        trailing: Semantics(
            label: title,
            child: CupertinoSwitch(
                value: value, activeTrackColor: accent, onChanged: onChanged)));

class ChatSearchPage extends StatefulWidget {
  const ChatSearchPage({required this.info, super.key});
  final ChatInfoPage info;
  @override
  State<ChatSearchPage> createState() => ChatSearchPageState();
}

class ChatSearchPageState extends State<ChatSearchPage> {
  Timer? _debounce;
  int _sequence = 0;
  bool _loading = false, _failed = false;
  String _query = '';
  List<ChatMessage> _results = [];

  void _search(String value) {
    _debounce?.cancel();
    final sequence = ++_sequence;
    final query = value.trim();
    setState(() {
      _query = query;
      _failed = false;
      _loading = query.isNotEmpty;
      _results = [];
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final gateway = widget.info.gateway;
        final id = widget.info.controller.conversationId;
        final results = gateway != null && id != null
            ? await gateway.searchChatMessages(id, query)
            : widget.info.controller.messages
                .where((message) => message.content.contains(query))
                .toList();
        if (mounted && sequence == _sequence) {
          setState(() => _results = results);
        }
      } catch (_) {
        if (mounted && sequence == _sequence) setState(() => _failed = true);
      } finally {
        if (mounted && sequence == _sequence) setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sequence++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: _pageColor,
      appBar: _appBar('查找聊天记录'),
      body: Column(children: [
        Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: TextField(
                autofocus: true,
                maxLength: 200,
                onChanged: _search,
                decoration: InputDecoration(
                    hintText: '搜索聊天内容',
                    counterText: '',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: _pageColor,
                    border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(10))))),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                    ? Center(
                        child: TextButton(
                            onPressed: () => _search(_query),
                            child: const Text('搜索失败，点击重试')))
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                                _query.isEmpty ? '输入关键词，查找这段对话' : '没有找到相关聊天记录',
                                style: const TextStyle(
                                    fontSize: 14, color: Color(0xFF929C96))))
                        : ListView.separated(
                            itemCount: _results.length,
                            separatorBuilder: (context, child) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final message = _results[index];
                              return Material(
                                  color: Colors.white,
                                  child: ListTile(
                                      title: Text(
                                          message.role == ChatRole.user
                                              ? '我'
                                              : widget.info.partnerName,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF929C96))),
                                      subtitle: Text(message.content,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 15,
                                              color: _ink,
                                              height: 1.5)),
                                      trailing: message.createdAt == null
                                          ? null
                                          : Text(_date(message.createdAt!),
                                              style: const TextStyle(
                                                  fontSize: 11)),
                                      onTap: () => Navigator.of(context)
                                          .push<void>(MaterialPageRoute(
                                              builder: (_) => Scaffold(
                                                  backgroundColor: _pageColor,
                                                  appBar: _appBar('聊天记录'),
                                                  body: SingleChildScrollView(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              20),
                                                      child: Column(children: [
                                                        if (message.createdAt !=
                                                            null)
                                                          Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          18),
                                                              child: Text(
                                                                  _date(message
                                                                      .createdAt!),
                                                                  style: const TextStyle(
                                                                      color: Color(
                                                                          0xFF929C96)))),
                                                        MessageBubble(
                                                            message: message,
                                                            assistantRole: widget
                                                                .info
                                                                .partnerRole,
                                                            imageUrlBuilder: widget
                                                                .info
                                                                .imageUrlBuilder,
                                                            imageAccessToken: widget
                                                                .info
                                                                .imageAccessToken),
                                                      ])))))));
                            })),
      ]));
}

String _date(DateTime date) {
  final local = date.toUtc().add(const Duration(hours: 8));
  return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
