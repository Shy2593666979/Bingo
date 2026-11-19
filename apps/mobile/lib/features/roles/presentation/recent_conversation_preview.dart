import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:bingo/features/chat/presentation/widgets/local_message_view.dart';
import 'dart:async';
import 'package:bingo/features/chat/presentation/widgets/location_card.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

/// Uses real messages and the same bubble renderer as the conversation page.
class RecentConversationPreview extends StatefulWidget {
  const RecentConversationPreview(
      {required this.role,
      required this.gateway,
      this.userAvatarData,
      this.userName = '',
      super.key});
  final RoleOption role;
  final RoleGateway gateway;
  final String? userAvatarData;
  final String userName;
  @override
  State<RecentConversationPreview> createState() =>
      _RecentConversationPreviewState();
}

class _RecentConversationPreviewState extends State<RecentConversationPreview> {
  late Future<List<ChatMessage>> _history;
  String? _account, _avatar;
  String _name = '';
  Future<void> _loadProfile() async {
    final gateway = widget.gateway;
    if (gateway is! HttpApiGateway) return;
    try {
      final profile = await gateway.getProfile();
      if (mounted) {
        setState(() {
          _account = profile.id;
          _avatar = profile.userAvatarData;
          _name = profile.username ?? '';
        });
      }
    } catch (_) {/* Text previews still work while profile is unavailable. */}
  }

  Widget _message(ChatMessage message, HttpApiGateway? http) {
    Widget render(Widget? voice) => MessageBubble(
        message: message,
        assistantRole: widget.role.name,
        imageUrlBuilder: http?.imageUrl,
        imageAccessToken: http?.accessToken,
        contentOverride: voice);
    if (_account == null) return render(null);
    return LocalMessageView(
        account: _account!,
        messageKey: 'message:${message.id}',
        text: message.content,
        isUser: message.role == ChatRole.user,
        builder: render);
  }

  Future<List<ChatMessage>> _load() async {
    final gateway = widget.gateway;
    if (gateway is! ConversationGateway || widget.role.conversationId == null) {
      return [];
    }
    final messages = await (gateway as ConversationGateway)
        .listMessages(widget.role.conversationId!);
    return messages.reversed.take(4).toList().reversed.toList();
  }

  @override
  void initState() {
    super.initState();
    _history = _load();
    unawaited(_loadProfile());
  }

  @override
  void didUpdateWidget(covariant RecentConversationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role) _history = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ChatMessage>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
              onPressed: () => setState(() => _history = _load()),
              child: const Text('加载失败，点击重试'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('还没有聊天记录，和 TA 打个招呼吧。'));
        }
        final http = widget.gateway is HttpApiGateway
            ? widget.gateway as HttpApiGateway
            : null;
        return ColoredBox(
            color: Colors.white,
            child: Column(children: [
              for (final message in snapshot.data!)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                            child: message.location == null
                                ? _message(message, http)
                                : Row(
                                    mainAxisAlignment:
                                        message.role == ChatRole.user
                                            ? MainAxisAlignment.end
                                            : MainAxisAlignment.start,
                                    children: [
                                        if (message.role != ChatRole.user) ...[
                                          AssistantAvatar(
                                              role: widget.role.name, size: 32),
                                          const SizedBox(width: 8)
                                        ],
                                        Flexible(
                                            child: LocationCard(
                                                location: message.location!,
                                                mapUrl: http?.locationMapUrl(
                                                    message.location!),
                                                accessToken: http?.accessToken,
                                                isUser: message.role ==
                                                    ChatRole.user)),
                                      ])),
                        if (message.role == ChatRole.user) ...[
                          const SizedBox(width: 8),
                          Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: UserAvatar(
                                  avatarData: widget.userAvatarData ?? _avatar,
                                  username: widget.userName.isEmpty
                                      ? _name
                                      : widget.userName,
                                  size: 32)),
                        ],
                      ],
                    )),
            ]));
      });
}
