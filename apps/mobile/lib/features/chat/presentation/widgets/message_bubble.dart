import 'package:bingo/core/design/chat_scene.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:bingo/features/stickers/sticker.dart';
import 'package:bingo/features/stickers/sticker_widgets.dart';
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/features/chat/presentation/widgets/companion_moment_card.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.assistantRole,
    this.imageUrlBuilder,
    this.showAvatar = true,
    this.imageAccessToken,
    this.onAvatarTap,
    this.onAvatarLongPress,
    this.contentOverride,
    super.key,
  });

  final ChatMessage message;
  final bool showAvatar;
  final String? assistantRole;
  final String Function(String imageId)? imageUrlBuilder;
  final String? imageAccessToken;
  final VoidCallback? onAvatarTap, onAvatarLongPress;
  final Widget? contentOverride;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final defaultStyle = AppearanceScope.of(context).bubble == 'mint';
    final sticker = ChatSticker.parse(message.content);
    if (sticker != null) {
      return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser) ...[
                      ChatPortrait(
                          key: ValueKey('chat-message-avatar-${message.id}'),
                          onTap: onAvatarTap,
                          onLongPress: onAvatarLongPress,
                          size: 36,
                          child: AssistantAvatar(
                              role: message.assistantRole ?? assistantRole,
                              size: 36)),
                      const SizedBox(width: 6)
                    ],
                    StickerMessageView(sticker),
                  ])));
    }

    final bubble = ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: math.min(defaultStyle ? 480 : 560,
                MediaQuery.sizeOf(context).width * (defaultStyle ? .72 : .8))),
        child: _MessageSurface(
          isUser: isUser,
          isMedia: message.imageBytes != null || message.imageId != null,
          padding: EdgeInsets.symmetric(
              horizontal: 12, vertical: defaultStyle ? 8 : 10),
          child: contentOverride ??
              (message.content.isEmpty
                  ? const _TypingDots()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.imageBytes != null)
                          _MemoryChatImage(bytes: message.imageBytes!)
                        else if (message.imageId != null &&
                            imageUrlBuilder != null)
                          _ChatImage(
                            url: imageUrlBuilder!(message.imageId!),
                            accessToken: imageAccessToken,
                          ),
                        if (isUser &&
                            CompanionMomentCard.matches(message.content))
                          CompanionMomentCard(content: message.content)
                        else if (message.imageId == null ||
                            message.content != '[图片]')
                          Text(
                            message.content,
                            style: TextStyle(
                              color: defaultStyle
                                  ? const Color(0xFF222222)
                                  : ChatScene.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              height: defaultStyle ? 1.35 : 1.4,
                              letterSpacing: 0,
                            ),
                          ),
                        if (message.status ==
                            ChatMessageStatus.interrupted) ...[
                          const SizedBox(height: 5),
                          Text(
                            '已中断',
                            style: TextStyle(
                              color: BingoPalette.ink.withValues(alpha: 0.48),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    )),
        ));

    final content = bubble;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
            top: defaultStyle
                ? 8
                : showAvatar
                    ? 5
                    : 1,
            bottom: defaultStyle ? 8 : 4),
        child: isUser
            ? content
            : Row(
                crossAxisAlignment: defaultStyle
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: defaultStyle ? 8 : 6),
                    child: showAvatar || defaultStyle
                        ? ChatPortrait(
                            key: ValueKey('chat-message-avatar-${message.id}'),
                            onTap: onAvatarTap,
                            onLongPress: onAvatarLongPress,
                            size: defaultStyle ? 32 : 36,
                            child: AssistantAvatar(
                                role: message.assistantRole ?? assistantRole,
                                size: defaultStyle ? 32 : 36))
                        : const SizedBox.square(dimension: 36),
                  ),
                  Flexible(child: content),
                ],
              ),
      ),
    );
  }
}

class _MessageSurface extends StatelessWidget {
  const _MessageSurface({
    required this.isUser,
    required this.isMedia,
    required this.padding,
    required this.child,
  });

  final bool isUser, isMedia;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => isMedia
      ? child
      : BubbleSurface(isUser: isUser, padding: padding, child: child);
}

class CallRecordTile extends StatelessWidget {
  const CallRecordTile({
    required this.message,
    this.assistantRole,
    this.onAvatarTap,
    this.onAvatarLongPress,
    super.key,
  });

  final ChatMessage message;
  final String? assistantRole;
  final VoidCallback? onAvatarTap, onAvatarLongPress;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(seconds: message.callDurationSeconds ?? 0);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final isUser = message.role == ChatRole.user;
    final status = message.callStatus;
    final failed = status == 'failed';
    final statusLabel = switch (status) {
      'rejected' => '已拒绝',
      'missed' => '未接来电',
      'failed' => '通话异常结束',
      _ => '通话已结束',
    };
    final bubble = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: BubbleSurface(
          isUser: isUser,
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                failed || status == 'rejected' || status == 'missed'
                    ? Icons.call_end_rounded
                    : Icons.call_rounded,
                size: 23,
                color: BingoPalette.ink,
              ),
              const SizedBox(width: 10),
              Flexible(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '语音通话',
                    style: TextStyle(
                      color: BingoPalette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$statusLabel  $minutes:$seconds',
                    style: TextStyle(
                      color: BingoPalette.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )),
            ],
          ),
        ));
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: isUser
            ? bubble
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 0),
                    child: ChatPortrait(
                        key: ValueKey('chat-message-avatar-${message.id}'),
                        onTap: onAvatarTap,
                        onLongPress: onAvatarLongPress,
                        size: 36,
                        child: AssistantAvatar(
                            role: message.assistantRole ?? assistantRole,
                            size: 36)),
                  ),
                  Flexible(child: bubble),
                ],
              ),
      ),
    );
  }
}

class _ChatImage extends StatelessWidget {
  const _ChatImage({required this.url, this.accessToken});

  final String url;
  final String? accessToken;

  Map<String, String>? get _headers =>
      accessToken == null ? null : {'Authorization': 'Bearer $accessToken'};

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      url,
      headers: _headers,
      width: 190,
      height: 190,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox(
        width: 190,
        height: 90,
        child: Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: InteractiveViewer(
            child: Image.network(url, headers: _headers, fit: BoxFit.contain),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: image,
      ),
    );
  }
}

class _MemoryChatImage extends StatelessWidget {
  const _MemoryChatImage({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          bytes,
          width: 190,
          height: 190,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class AssistantTypingBubble extends StatelessWidget {
  const AssistantTypingBubble({required this.assistantRole, super.key});

  final String? assistantRole;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 0),
              child: ChatPortrait(
                  size: 36,
                  child: AssistantAvatar(role: assistantRole, size: 36)),
            ),
            BubbleSurface(
              isUser: false,
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
              child: const _TypingDots(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          final phase = _controller.value * math.pi * 2 - index * 0.75;
          final progress = (math.sin(phase) + 1) / 2;
          return Transform.translate(
            offset: Offset(0, -4 * progress),
            child: Container(
              key: ValueKey('typing-dot-$index'),
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: AppearanceScope.skin(context).accent.withValues(
                      alpha: 0.42 + progress * 0.58,
                    ),
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }
}
