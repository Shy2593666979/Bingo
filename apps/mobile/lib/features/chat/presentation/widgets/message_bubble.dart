import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.assistantRole,
    this.imageUrlBuilder,
    this.imageAccessToken,
    super.key,
  });

  final ChatMessage message;
  final String? assistantRole;
  final String Function(String imageId)? imageUrlBuilder;
  final String? imageAccessToken;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: isUser
            ? BingoPalette.userBubble
            : BingoPalette.softSurface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(26),
          topRight: const Radius.circular(26),
          bottomLeft: Radius.circular(isUser ? 26 : 8),
          bottomRight: Radius.circular(isUser ? 8 : 26),
        ),
        border: isUser ? null : Border.all(color: Colors.white),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08205F4F),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: message.content.isEmpty
          ? const _TypingDots()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.imageBytes != null)
                  _MemoryChatImage(bytes: message.imageBytes!)
                else if (message.imageId != null && imageUrlBuilder != null)
                  _ChatImage(
                    url: imageUrlBuilder!(message.imageId!),
                    accessToken: imageAccessToken,
                  ),
                if (message.imageId == null || message.content != '[图片]')
                  SelectableText(
                    message.content,
                    style: TextStyle(
                      color: BingoPalette.ink,
                      fontSize: 16,
                      height: 1.55,
                    ),
                  ),
                if (message.status == ChatMessageStatus.interrupted) ...[
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
            ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: isUser
            ? bubble
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 9, bottom: 6),
                    child: AssistantAvatar(
                      role: message.assistantRole ?? assistantRole,
                      size: 42,
                    ),
                  ),
                  Flexible(child: bubble),
                ],
              ),
      ),
    );
  }
}

class CallRecordTile extends StatelessWidget {
  const CallRecordTile({
    required this.message,
    this.assistantRole,
    super.key,
  });

  final ChatMessage message;
  final String? assistantRole;

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
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      decoration: BoxDecoration(
        color: isUser ? BingoPalette.userBubble : BingoPalette.softSurface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(isUser ? 22 : 7),
          bottomRight: Radius.circular(isUser ? 7 : 22),
        ),
        border: isUser ? null : Border.all(color: Colors.white),
      ),
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
          Column(
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
                  color: const Color(0xFF65716D),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                    padding: const EdgeInsets.only(right: 9, bottom: 6),
                    child: AssistantAvatar(
                      role: message.assistantRole ?? assistantRole,
                      size: 42,
                    ),
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
      fit: BoxFit.cover,
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
          fit: BoxFit.cover,
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
              padding: const EdgeInsets.only(right: 9, bottom: 6),
              child: AssistantAvatar(role: assistantRole, size: 42),
            ),
            Container(
              width: 66,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BingoPalette.softSurface.withValues(alpha: 0.94),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(26),
                  topRight: Radius.circular(26),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(26),
                ),
                border: Border.all(color: Colors.white),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08205F4F),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
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
                color: BingoPalette.blue.withValues(
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
