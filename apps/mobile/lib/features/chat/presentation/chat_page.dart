import 'dart:async';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_starters.dart';
import 'package:bingo/features/chat/presentation/widgets/device_action_card.dart';
import 'package:bingo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
import 'package:flutter/material.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.controller,
    required this.assistantName,
    required this.assistantRole,
    required this.speechGateway,
    required this.onStartCall,
    required this.onIncomingCall,
    this.onPickGallery,
    this.onTakePhoto,
    this.imageUrlBuilder,
    this.imageAccessToken,
    required this.onOpenSettings,
    this.onBack,
    super.key,
  });

  final ChatController controller;
  final String assistantName;
  final String? assistantRole;
  final SpeechGateway speechGateway;
  final VoidCallback onStartCall;
  final Future<void> Function(IncomingCallInvitation invitation) onIncomingCall;
  final VoidCallback? onPickGallery;
  final VoidCallback? onTakePhoto;
  final String Function(String imageId)? imageUrlBuilder;
  final String? imageAccessToken;
  final VoidCallback onOpenSettings;
  final VoidCallback? onBack;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.setAssistantRole(widget.assistantRole);
    widget.controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onChanged();
      _jumpToBottom();
    });
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
    if (oldWidget.assistantRole != widget.assistantRole ||
        oldWidget.controller != widget.controller) {
      widget.controller.setAssistantRole(widget.assistantRole);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final incomingCall = widget.controller.takeIncomingCall();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (incomingCall != null && mounted) {
        unawaited(widget.onIncomingCall(incomingCall));
      }
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _jumpToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    // A lazily built long list can refine its extent after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final showWaiting = controller.isBusy;
    final showRecommendations =
        !showWaiting && controller.recommendations.isNotEmpty;
    return Scaffold(
      body: CustomPaint(
        painter: const _MintBackgroundPainter(),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _ChatHeader(
                assistantName: widget.assistantName,
                assistantRole: widget.assistantRole,
                onOpenSettings: widget.onOpenSettings,
                onBack: widget.onBack,
              ),
              if (controller.errorMessage case final message?)
                Container(
                  margin: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded),
                    const SizedBox(width: 10),
                    Expanded(child: Text(message)),
                    IconButton(
                      onPressed: controller.dismissError,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                ),
              Expanded(
                child: controller.timelineItems.isEmpty &&
                        !showWaiting &&
                        !showRecommendations
                    ? _EmptyChat(
                        onSuggestion: controller.send,
                        assistantRole: widget.assistantRole)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                        itemCount: controller.timelineItems.length +
                            (showWaiting || showRecommendations ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == controller.timelineItems.length) {
                            if (showWaiting) {
                              return AssistantTypingBubble(
                                assistantRole: widget.assistantRole,
                              );
                            }
                            return _RecommendationRows(
                              items: controller.recommendations,
                              onSelected: controller.sendRecommendation,
                            );
                          }
                          final item = controller.timelineItems[index];
                          if (item case final ChatMessage message) {
                            final showTime = _shouldShowTime(
                              controller.timelineItems,
                              index,
                            );
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showTime)
                                  _MessageTimeDivider(
                                    value: message.createdAt!,
                                  ),
                                if (message.type == ChatMessageType.call)
                                  CallRecordTile(
                                    message: message,
                                    assistantRole: widget.assistantRole,
                                  )
                                else
                                  MessageBubble(
                                    message: message,
                                    assistantRole: widget.assistantRole,
                                    imageUrlBuilder: widget.imageUrlBuilder,
                                    imageAccessToken: widget.imageAccessToken,
                                  ),
                              ],
                            );
                          }
                          if (item case final DeviceAction action) {
                            return DeviceActionCard(
                              action: action,
                              onApprove: () =>
                                  controller.approveDeviceAction(action),
                              onReject: () =>
                                  controller.rejectDeviceAction(action),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
              ),
              MessageInput(
                enabled: true,
                onSend: controller.send,
                speechGateway: widget.speechGateway,
                onCall: widget.onStartCall,
                onGallery: widget.onPickGallery,
                onCamera: widget.onTakePhoto,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowTime(List<Object> items, int index) {
    final current = items[index];
    if (current is! ChatMessage || current.createdAt == null) return false;
    for (var previousIndex = index - 1; previousIndex >= 0; previousIndex--) {
      final previous = items[previousIndex];
      if (previous is! ChatMessage) continue;
      final previousTime = previous.createdAt;
      if (previousTime == null) return true;
      return current.createdAt!.difference(previousTime) >
          const Duration(minutes: 10);
    }
    return true;
  }
}

class _MessageTimeDivider extends StatelessWidget {
  const _MessageTimeDivider({required this.value});

  final DateTime value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 11, 0, 5),
      child: Center(
        child: Text(
          _format(value),
          style: const TextStyle(
            color: Color(0xFF89938F),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _format(DateTime value) {
    final local = value.toUtc().add(const Duration(hours: 8));
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (messageDay == today) return time;
    if (messageDay == today.subtract(const Duration(days: 1))) {
      return '昨天 $time';
    }
    if (local.year == now.year) {
      return '${local.month}月${local.day}日 $time';
    }
    return '${local.year}年${local.month}月${local.day}日 $time';
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.assistantName,
    required this.assistantRole,
    required this.onOpenSettings,
    this.onBack,
  });

  final String assistantName;
  final String? assistantRole;
  final VoidCallback onOpenSettings;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 18, 14),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
                onPressed: onBack,
                tooltip: '返回角色',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 21)),
            const SizedBox(width: 4),
          ],
          AssistantAvatar(
            role: assistantRole,
            size: 62,
            showOnline: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              assistantName,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MintBackgroundPainter extends CustomPainter {
  const _MintBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final topPath = Path()
      ..moveTo(size.width * 0.68, 0)
      ..quadraticBezierTo(
          size.width * 0.88, size.height * 0.13, size.width, 180)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(
      topPath,
      Paint()..color = const Color(0xFFE1F7EF).withValues(alpha: 0.58),
    );

    final bottomPath = Path()
      ..moveTo(0, size.height * 0.77)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.91,
        size.width,
        size.height * 0.74,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      bottomPath,
      Paint()..color = const Color(0xFFE7F9F3).withValues(alpha: 0.64),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RecommendationRows extends StatelessWidget {
  const _RecommendationRows({
    required this.items,
    required this.onSelected,
  });

  final List<String> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDDF4EB),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 14, color: BingoPalette.blue),
                  const SizedBox(width: 5),
                  const Text(
                    '为您推荐',
                    style: TextStyle(
                      color: BingoPalette.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onSelected(item),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8F5).withValues(alpha: 0.96),
                    border: Border.all(color: const Color(0xFFDCECE6)),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A205F4F),
                        blurRadius: 12,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    item,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onSuggestion, this.assistantRole});

  final ValueChanged<String> onSuggestion;
  final String? assistantRole;

  @override
  Widget build(BuildContext context) {
    final suggestions = chatStartersForRole(assistantRole);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              key: const ValueKey('empty-chat-avatar'),
              dimension: 104,
              child: Center(
                child: AssistantAvatar(role: assistantRole, size: 88),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              '今天想聊点什么？',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 24),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var index = 0; index < 2; index++) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Flexible(child: _suggestion(suggestions[index])),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                _suggestion(suggestions[2]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestion(String text) => ActionChip(
        label: Text(text,
            textAlign: TextAlign.center, softWrap: true, maxLines: 3),
        onPressed: () => onSuggestion(text),
      );
}
