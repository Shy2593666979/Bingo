import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/roles/role_traits.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:bingo/features/chat/presentation/widgets/location_card.dart';
import 'package:flutter/material.dart';

class RoleDetailPage extends StatefulWidget {
  const RoleDetailPage(
      {required this.role,
      required this.gateway,
      required this.onChat,
      this.onEdit,
      this.userAvatarData,
      super.key});
  final RoleOption role;
  final RoleGateway gateway;
  final Future<void> Function(RoleOption) onChat;
  final Future<void> Function()? onEdit;
  final String? userAvatarData;
  @override
  State<RoleDetailPage> createState() => _RoleDetailPageState();
}

class _RoleDetailPageState extends State<RoleDetailPage> {
  List<ChatMessage>? _messages;
  bool _busy = false;
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

  Widget _surface(Widget child) => Container(
      padding: const EdgeInsets.all(22),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(30)),
      child: child);
  @override
  Widget build(BuildContext context) {
    final role = _role;
    return Scaffold(
      backgroundColor: BingoPalette.ice,
      appBar: AppBar(title: const Text('伙伴详情'), centerTitle: true, actions: [
        if (widget.onEdit != null)
          IconButton(
              tooltip: '编辑伙伴',
              onPressed: _edit,
              icon: const Icon(Icons.tune_rounded))
      ]),
      body: DecoratedBox(
          decoration: const BoxDecoration(gradient: BingoPalette.softGradient),
          child: ListView(padding: const EdgeInsets.all(18), children: [
            _surface(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                AssistantAvatar(role: role.name, size: 102),
                const SizedBox(width: 18),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(role.displayName,
                          style: const TextStyle(
                              fontSize: 29, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 7),
                      Text(role.typeLabel.isEmpty ? '陪伴伙伴' : role.typeLabel,
                          style: const TextStyle(
                              color: Color(0xFF7D918A), fontSize: 14)),
                    ])),
              ]),
              const SizedBox(height: 16),
              Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: role.traits.map(TraitBadge.new).toList()),
              const SizedBox(height: 18),
              Text(role.description.isEmpty ? role.prompt : role.description,
                  style:
                      const TextStyle(color: Color(0xFF7D918A), height: 1.6)),
            ])),
            _surface(Row(children: [
              Expanded(
                  child: _stat(
                      '伙伴身份',
                      role.typeLabel.isEmpty ? '陪伴伙伴' : role.typeLabel,
                      'heart')),
              Expanded(child: _stat('对话消息', '${role.messageCount} 条', 'chat')),
              Expanded(child: _stat('未读消息', '${role.unreadCount} 条', 'book'))
            ])),
            _surface(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                TraitIcon('chat', size: 25),
                SizedBox(width: 10),
                Text('最近对话',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))
              ]),
              const SizedBox(height: 20),
              if (_error != null) Text(_error!),
              if (_messages == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_messages?.isEmpty ?? false)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 25),
                    child: Text('还没有聊天记录，和 TA 打个招呼吧。',
                        style: TextStyle(color: Color(0xFF7D918A)))),
              ...?_messages?.map((message) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                      mainAxisAlignment: message.role == ChatRole.user
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.role != ChatRole.user) ...[
                          AssistantAvatar(role: role.name, size: 34),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                            child: message.location != null
                                ? LocationCard(
                                    isUser: message.role == ChatRole.user,
                                    location: message.location!,
                                    mapUrl: message.location!.hasCoordinates &&
                                            widget.gateway is LocationGateway
                                        ? (widget.gateway as LocationGateway)
                                            .locationMapUrl(message.location!)
                                        : null,
                                    accessToken:
                                        widget.gateway is HttpApiGateway
                                            ? (widget.gateway as HttpApiGateway)
                                                .accessToken
                                            : null)
                                : Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                        color: message.role == ChatRole.user
                                            ? BingoPalette.userBubble
                                            : const Color(0xFFEDF8F5),
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    child: Text(
                                        message.content.isEmpty ? '[图片或通话消息]' : message.content,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(height: 1.5)))),
                        if (message.role == ChatRole.user) ...[
                          const SizedBox(width: 10),
                          UserAvatar(
                              avatarData: widget.userAvatarData, size: 34),
                        ],
                      ]))),
            ])),
          ])),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Expanded(
                    child: FilledButton.icon(
                        onPressed: _busy ? null : _chat,
                        icon: const Icon(Icons.chat_bubble_rounded),
                        label: Text(_busy ? '正在进入…' : '进入聊天'))),
                if (widget.onEdit != null) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                      onPressed: _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑伙伴'))
                ],
              ]))),
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

  Widget _stat(String label, String value, String icon) => Column(children: [
        TraitIcon(icon, size: 25),
        const SizedBox(height: 9),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF7D918A))),
        const SizedBox(height: 6),
        FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700))),
      ]);
}
