import 'package:bingo/core/design/bingo_page.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/design/bingo_surface.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/stickers/sticker.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:bingo/shared/widgets/partner_action_icon.dart';
import 'package:flutter/material.dart';

class RoleDetailPage extends StatefulWidget {
  const RoleDetailPage(
      {required this.role,
      required this.gateway,
      required this.onChat,
      this.onEdit,
      this.onShare,
      this.userAvatarData,
      this.userName = '',
      super.key});
  final RoleOption role;
  final RoleGateway gateway;
  final Future<void> Function(RoleOption) onChat;
  final Future<void> Function()? onEdit;
  final Future<void> Function(RoleOption)? onShare;
  final String? userAvatarData;
  final String userName;
  @override
  State<RoleDetailPage> createState() => _RoleDetailPageState();
}

class _RoleDetailPageState extends State<RoleDetailPage> {
  List<ChatMessage>? _messages;
  bool _busy = false;
  bool _backgroundExpanded = false;
  String? _error;
  late RoleOption _role;
  @override
  void initState() {
    super.initState();
    _role = widget.role;
    _load();
  }

  Future<void> _load() async {
    final gateway = widget.gateway;
    if (_role.conversationId == null || gateway is! ConversationGateway) {
      _messages = [];
      return;
    }
    try {
      final messages = await (gateway as ConversationGateway)
          .listMessages(_role.conversationId!);
      if (mounted) {
        setState(() =>
            _messages = messages.reversed.take(4).toList().reversed.toList());
      }
    } on Exception {
      if (mounted) setState(() => _error = '历史消息加载失败，请稍后重试');
    }
  }

  Future<void> _chat() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onChat(_role);
      final roles = await widget.gateway.listRoles();
      if (mounted) {
        setState(() => _role =
            roles.where((role) => role.id == _role.id).firstOrNull ?? _role);
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _surface(Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(16),
          child: Padding(padding: const EdgeInsets.all(18), child: child)));

  Widget _tags(List<String> tags) => Wrap(spacing: 7, runSpacing: 7, children: [
        for (final tag in tags)
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: BingoPalette.line)),
              child: Text(tag,
                  style: const TextStyle(
                      fontSize: 12, height: 1.35, color: Color(0xFF666666))))
      ]);

  String _messageTime(DateTime value) {
    final local = value.toUtc().add(const Duration(hours: 8));
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final role = _role;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('搭子详情'), centerTitle: true, actions: [
        if (widget.onShare != null)
          IconButton(
              tooltip: '分享搭子',
              onPressed: _busy ? null : () => widget.onShare!(_role),
              icon: const Icon(Icons.ios_share_rounded, size: 21)),
        if (widget.onEdit != null)
          IconButton(
              tooltip: '编辑搭子',
              onPressed: _edit,
              icon: const Icon(Icons.tune_rounded))
      ]),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 26),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AssistantAvatar(
                          role: role.name, size: 84, closePortrait: true),
                      const SizedBox(width: 18),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(role.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 22,
                                    height: 1.3,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 7),
                            Text(
                                role.typeLabel.isEmpty
                                    ? '陪伴搭子'
                                    : role.typeLabel,
                                style: const TextStyle(
                                    fontSize: 14, color: BingoPalette.muted)),
                            const SizedBox(height: 10),
                            Text(
                                role.builtin
                                    ? 'Bingo 官方搭子'
                                    : role.sourcePublicationId != null
                                        ? '来自社区的搭子'
                                        : '我创建的搭子',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF999999))),
                          ])),
                    ])),
            _surface(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BingoSectionTitle('关于TA'),
              const SizedBox(height: 10),
              Text(
                  role.description.isNotEmpty
                      ? role.description
                      : '和喜欢的搭子，分享生活里的每个瞬间。',
                  style: const TextStyle(
                      fontSize: 14, height: 1.7, color: Color(0xFF555555))),
            ])),
            _surface(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BingoSectionTitle('说话风格'),
              const SizedBox(height: 10),
              Text(role.speakingStyle,
                  style: const TextStyle(
                      fontSize: 14, height: 1.6, color: Color(0xFF555555))),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1, color: BingoPalette.line)),
              const BingoSectionTitle('性格标签'),
              const SizedBox(height: 12),
              _tags(role.personalityTags),
            ])),
            if (role.background.isNotEmpty)
              _surface(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BingoSectionTitle('人物背景'),
                    const SizedBox(height: 10),
                    Text(role.background,
                        maxLines: _backgroundExpanded ? null : 5,
                        overflow: _backgroundExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            height: 1.7,
                            color: Color(0xFF555555))),
                    if (role.background.length > 100 ||
                        '\n'.allMatches(role.background).length > 4)
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: () => setState(() =>
                                  _backgroundExpanded = !_backgroundExpanded),
                              child: Text(_backgroundExpanded ? '收起背景' : '展开背景',
                                  style: const TextStyle(fontSize: 12)))),
                  ])),
            _surface(Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.mic_none_rounded,
                      size: 22, color: Color(0xFF555555))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const BingoSectionTitle('人物声音'),
                    const SizedBox(height: 4),
                    Text(
                        role.voiceName?.isNotEmpty == true
                            ? role.voiceName!
                            : role.hasVoice
                                ? '已设置专属声音'
                                : '暂未设置声音',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: BingoPalette.muted)),
                  ])),
            ])),
            _surface(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BingoSectionTitle('最近对话'),
              const SizedBox(height: 12),
              if (_error != null) Text(_error!),
              if (_messages == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_messages?.isEmpty ?? false)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 25),
                    child: Text('还没有聊天记录，和 TA 打个招呼吧。',
                        style: TextStyle(color: BingoPalette.muted))),
              ...?_messages?.map((message) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.role == ChatRole.user)
                          UserAvatar(
                              avatarData: widget.userAvatarData,
                              username: widget.userName,
                              size: 40)
                        else
                          AssistantAvatar(role: role.name, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                    child: Text(
                                        message.role == ChatRole.user
                                            ? '我'
                                            : role.displayName,
                                        maxLines: 1,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500))),
                                if (message.createdAt != null)
                                  Text(_messageTime(message.createdAt!),
                                      style: const TextStyle(
                                          fontSize: 10, color: refMuted))
                              ]),
                              const SizedBox(height: 6),
                              Text(
                                  message.location != null
                                      ? '[位置] ${message.location!.name}'
                                      : ChatSticker.preview(
                                          message.content.isEmpty
                                              ? '[图片或通话消息]'
                                              : message.content),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: refMuted))
                            ]))
                      ]))),
            ])),
          ]),
      bottomNavigationBar: BingoActionBar(
          child: Row(children: [
        if (widget.onEdit != null) ...[
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: _edit,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: BingoPalette.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                  icon:
                      const PartnerActionIcon(symbol: PartnerActionSymbol.edit),
                  label: const Text('编辑搭子'))),
          const SizedBox(width: 12)
        ],
        Expanded(
            child: FilledButton.icon(
                onPressed: _busy ? null : _chat,
                style: FilledButton.styleFrom(
                    backgroundColor: BingoPalette.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 10)),
                icon: const PartnerActionIcon(
                    symbol: PartnerActionSymbol.chat,
                    size: 20,
                    color: Colors.white),
                label: Text(_busy ? '正在进入…' : '进入聊天',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600))))
      ])),
    );
  }

  Future<void> _edit() async {
    await widget.onEdit?.call();
    if (!mounted) return;
    final roles = await widget.gateway.listRoles();
    if (!mounted) return;
    final updated = roles.where((role) => role.id == _role.id).firstOrNull;
    if (updated == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => _role = updated);
  }
}
