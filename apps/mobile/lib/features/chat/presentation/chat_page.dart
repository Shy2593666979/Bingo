import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/features/chat/presentation/chat_info_page.dart';
import 'dart:async';
import 'package:bingo/core/design/chat_scene.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/models/moment_completion.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_starters.dart';
import 'package:bingo/features/chat/presentation/companion_moment_page.dart';
import 'package:bingo/features/chat/presentation/widgets/device_action_card.dart';
import 'package:bingo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
import 'package:bingo/features/chat/presentation/widgets/chat_typing_hint.dart';
import 'package:flutter/material.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:bingo/features/chat/presentation/widgets/location_card.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    this.appearanceStore,
    this.appearanceRoleId,
    required this.controller,
    required this.assistantName,
    required this.assistantRole,
    required this.speechGateway,
    required this.onStartCall,
    required this.onIncomingCall,
    this.onPickGallery,
    this.onTakePhoto,
    this.onLocation,
    this.locationMapUrlBuilder,
    this.userAvatarData,
    this.imageUrlBuilder,
    this.imageAccessToken,
    required this.onOpenSettings,
    this.onBack,
    this.infoGateway,
    this.onOpenRoleDetails,
    super.key,
  });

  final AppearanceStore? appearanceStore;
  final String? appearanceRoleId;
  final ChatController controller;
  final String assistantName;
  final String? assistantRole;
  final SpeechGateway speechGateway;
  final VoidCallback onStartCall;
  final Future<void> Function(IncomingCallInvitation invitation) onIncomingCall;
  final VoidCallback? onPickGallery;
  final VoidCallback? onTakePhoto;
  final VoidCallback? onLocation;
  final String Function(ChatLocation)? locationMapUrlBuilder;
  final String? userAvatarData;
  final String Function(String imageId)? imageUrlBuilder;
  final String? imageAccessToken;
  final VoidCallback onOpenSettings;
  final VoidCallback? onBack;
  final ChatInfoGateway? infoGateway;
  final VoidCallback? onOpenRoleDetails;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _inputKey = GlobalKey<MessageInputState>();
  int _lastTimelineLength = 0;
  int _lastRecommendationsLength = 0;
  String? _lastMessageContent;
  bool _lastBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(ChatScene.setNativeChrome(true));
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.controller.activateSpeech());
    widget.controller.setAssistantRole(widget.assistantRole);
    widget.controller.addListener(_onChanged);
    widget.appearanceStore?.addListener(_onAppearanceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onChanged();
      _jumpToBottom();
    });
  }

  void _onAppearanceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearanceStore != widget.appearanceStore) {
      oldWidget.appearanceStore?.removeListener(_onAppearanceChanged);
      widget.appearanceStore?.addListener(_onAppearanceChanged);
    }
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
    unawaited(ChatScene.setNativeChrome(false));
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.deactivateSpeech();
    widget.controller.removeListener(_onChanged);
    widget.appearanceStore?.removeListener(_onAppearanceChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.activateSpeech());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.controller.deactivateSpeech();
    }
  }

  ChatInfoPage _chatInfo() => ChatInfoPage(
      controller: widget.controller,
      partnerName: widget.assistantName,
      partnerRole: widget.assistantRole,
      onCall: _startCall,
      gateway: widget.infoGateway,
      appearanceStore: widget.appearanceStore,
      roleId: widget.appearanceRoleId,
      imageUrlBuilder: widget.imageUrlBuilder,
      imageAccessToken: widget.imageAccessToken);

  Future<void> _openMoment(CompanionMoment kind) async {
    await widget.controller.stopSpeech();
    if (!mounted) return;
    final route = MaterialPageRoute<MomentCompletion>(
        builder: (_) => CompanionMomentPage(
            kind: kind,
            controller: widget.controller,
            partnerName: widget.assistantName,
            partnerRole: widget.assistantRole));
    final completion = await Navigator.of(context).push(route);
    await route.completed;
    if (!mounted ||
        completion == null ||
        widget.controller.userId != completion.userId ||
        widget.controller.conversationId != completion.conversationId) {
      return;
    }
    await widget.controller.sendMomentSummary(
        completion.feature, completion.summary, completion.sessionId);
  }

  void _startCall() {
    unawaited(widget.controller.stopSpeech());
    widget.onStartCall();
  }

  void _insertPartnerName() =>
      _inputKey.currentState?.insertText('${widget.assistantName} ');

  void _onChanged() {
    if (!mounted) return;
    final controller = widget.controller;
    final lastContent = controller.messages.lastOrNull?.content;
    final recommendationDockChanged =
        controller.recommendations.length != _lastRecommendationsLength;
    final nearBottom = _scrollController.hasClients &&
        _scrollController.position.extentAfter < 48;
    final shouldScroll =
        controller.timelineItems.length != _lastTimelineLength ||
            lastContent != _lastMessageContent ||
            controller.isBusy != _lastBusy ||
            (recommendationDockChanged && nearBottom);
    _lastTimelineLength = controller.timelineItems.length;
    _lastMessageContent = lastContent;
    _lastBusy = controller.isBusy;
    _lastRecommendationsLength = controller.recommendations.length;
    final incomingCall = widget.controller.takeIncomingCall();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (incomingCall != null && mounted) {
        unawaited(widget.onIncomingCall(incomingCall));
      }
      if (mounted && shouldScroll && _scrollController.hasClients) {
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
    final showRecommendations =
        !controller.isBusy && controller.recommendations.isNotEmpty;
    final recommendationItems = showRecommendations
        ? controller.recommendations
        : controller.timelineItems.isEmpty && !controller.isBusy
            ? chatStartersForRole(widget.assistantRole)
            : const <String>[];
    final appearance =
        widget.appearanceStore?.effective(widget.appearanceRoleId) ??
            const ChatAppearance();
    final skin = ChatSkin.find(appearance.bubble);
    final baseTheme = buildMintTheme(context);
    return AppearanceScope(
        value: appearance,
        child: Theme(
          data: baseTheme.copyWith(
              colorScheme: baseTheme.colorScheme
                  .copyWith(primary: skin.accent, primaryContainer: skin.user)),
          child: Scaffold(
            body: ChatWallpaper(
              value: appearance,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _ChatHeader(
                      onAvatarTap: widget.onOpenRoleDetails,
                      onAvatarLongPress: _insertPartnerName,
                      assistantName: widget.assistantName,
                      onBack: widget.onBack,
                      assistantRole: widget.assistantRole,
                      onSearch: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                              builder: (_) =>
                                  ChatSearchPage(info: _chatInfo()))),
                      onInfo: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => _chatInfo())),
                    ),
                    if (controller.speechError case final message?)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(message,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF71817D)))),
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
                      child: Stack(children: [
                        Positioned.fill(
                            child: controller.timelineItems.isEmpty &&
                                    !controller.isWaitingForReply
                                ? _EmptyChat(
                                    onAvatarTap: widget.onOpenRoleDetails,
                                    onAvatarLongPress: _insertPartnerName,
                                    assistantRole: widget.assistantRole)
                                : ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 8, 12, 14),
                                    itemCount: controller.timelineItems.length +
                                        (controller.isWaitingForReply ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index ==
                                          controller.timelineItems.length) {
                                        return ChatTypingHint(
                                            onAvatarTap:
                                                widget.onOpenRoleDetails,
                                            onAvatarLongPress:
                                                _insertPartnerName,
                                            name: widget.assistantName,
                                            role: widget.assistantRole);
                                      }
                                      final item =
                                          controller.timelineItems[index];
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
                                            if (message.type ==
                                                ChatMessageType.call)
                                              CallRecordTile(
                                                onAvatarTap:
                                                    widget.onOpenRoleDetails,
                                                onAvatarLongPress:
                                                    _insertPartnerName,
                                                message: message,
                                                assistantRole:
                                                    widget.assistantRole,
                                              )
                                            else if (message.location != null)
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 8),
                                                  child: Row(
                                                      mainAxisAlignment: message
                                                                  .role ==
                                                              ChatRole.user
                                                          ? MainAxisAlignment
                                                              .end
                                                          : MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        if (message.role !=
                                                            ChatRole.user) ...[
                                                          ChatPortrait(
                                                              key: ValueKey(
                                                                  'chat-message-avatar-${message.id}'),
                                                              size: 34,
                                                              onTap: widget
                                                                  .onOpenRoleDetails,
                                                              onLongPress:
                                                                  _insertPartnerName,
                                                              child: AssistantAvatar(
                                                                  role: widget
                                                                      .assistantRole,
                                                                  size: 34)),
                                                          const SizedBox(
                                                              width: 9),
                                                        ],
                                                        Flexible(
                                                            child: LocationCard(
                                                                isUser: message
                                                                        .role ==
                                                                    ChatRole
                                                                        .user,
                                                                location: message
                                                                    .location!,
                                                                mapUrl: message
                                                                        .location!
                                                                        .hasCoordinates
                                                                    ? widget
                                                                        .locationMapUrlBuilder
                                                                        ?.call(message
                                                                            .location!)
                                                                    : null,
                                                                accessToken: widget
                                                                    .imageAccessToken)),
                                                      ]))
                                            else
                                              MessageBubble(
                                                onAvatarTap:
                                                    widget.onOpenRoleDetails,
                                                onAvatarLongPress:
                                                    _insertPartnerName,
                                                message: message,
                                                showAvatar:
                                                    !_continuesAssistant(
                                                        controller
                                                            .timelineItems,
                                                        index),
                                                assistantRole:
                                                    widget.assistantRole,
                                                imageUrlBuilder:
                                                    widget.imageUrlBuilder,
                                                imageAccessToken:
                                                    widget.imageAccessToken,
                                              ),
                                          ],
                                        );
                                      }
                                      if (item case final DeviceAction action) {
                                        return DeviceActionCard(
                                          onAvatarTap: widget.onOpenRoleDetails,
                                          onAvatarLongPress: _insertPartnerName,
                                          key: ValueKey(
                                              'device-action-${action.id}'),
                                          action: action,
                                          assistantRole: widget.assistantRole,
                                          onApprove: () => controller
                                              .approveDeviceAction(action),
                                          onReject: () => controller
                                              .rejectDeviceAction(action),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  )),
                      ]),
                    ),
                    if (recommendationItems.isNotEmpty)
                      Padding(
                          key: const ValueKey('chat-recommendations-dock'),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _RecommendationRows(
                              items: recommendationItems,
                              onSelected: showRecommendations
                                  ? controller.sendRecommendation
                                  : controller.send)),
                    MessageInput(
                      key: _inputKey,
                      initialVoiceMode: false,
                      referenceStyle: true,
                      hintText: '和${widget.assistantName}说点什么…',
                      enabled: true,
                      onSend: controller.send,
                      speechGateway: widget.speechGateway,
                      onCall: _startCall,
                      onMoment: _openMoment,
                      onGallery: widget.onPickGallery,
                      onCamera: widget.onTakePhoto,
                      onLocation: widget.onLocation,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
  }

  bool _continuesAssistant(List<Object> items, int index) {
    if (index == 0) return false;
    final current = items[index], previous = items[index - 1];
    if (current is! ChatMessage ||
        previous is! ChatMessage ||
        current.role != ChatRole.assistant ||
        previous.role != ChatRole.assistant ||
        current.type != ChatMessageType.chat ||
        previous.type != ChatMessageType.chat ||
        current.location != null ||
        previous.location != null ||
        current.assistantRole != previous.assistantRole ||
        current.createdAt == null ||
        previous.createdAt == null) {
      return false;
    }
    final gap = current.createdAt!.difference(previous.createdAt!);
    return !gap.isNegative && gap <= const Duration(minutes: 2);
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
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 9),
      child: Center(
          child: Text(_format(value),
              style: const TextStyle(
                  color: ChatScene.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w400))),
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
  const _ChatHeader(
      {required this.assistantName,
      required this.assistantRole,
      this.onBack,
      this.onAvatarTap,
      this.onAvatarLongPress,
      required this.onInfo,
      required this.onSearch});
  final String assistantName;
  final String? assistantRole;
  final VoidCallback? onBack;
  final VoidCallback onInfo, onSearch;
  final VoidCallback? onAvatarTap, onAvatarLongPress;

  @override
  Widget build(BuildContext context) => ChatGlass(
      child: Container(
          decoration: const BoxDecoration(color: Colors.transparent),
          padding: const EdgeInsets.fromLTRB(8, 7, 10, 11),
          child: Row(children: [
            IconButton(
                onPressed: onBack ?? () => Navigator.maybePop(context),
                tooltip: '返回角色',
                icon: const Icon(Icons.chevron_left_rounded,
                    size: 25, color: ChatScene.ink)),
            ChatPortrait(
                key: const ValueKey('chat-header-avatar'),
                onTap: onAvatarTap,
                onLongPress: onAvatarLongPress,
                size: 36,
                child: AssistantAvatar(role: assistantRole, size: 36)),
            const SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Flexible(
                        child: Text(assistantName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: ChatScene.ink))),
                    const SizedBox(width: 7),
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.transparent,
                            border: Border.all(color: const Color(0xFFB9DED2)),
                            borderRadius: BorderRadius.circular(3)),
                        child: const Text('AI',
                            style: TextStyle(
                                fontSize: 10,
                                color: BingoPalette.primary,
                                fontWeight: FontWeight.w700)))
                  ]),
                ])),
            IconButton(
                onPressed: onSearch,
                tooltip: '查找聊天记录',
                icon: const Icon(Icons.search_rounded,
                    size: 21, color: ChatScene.ink)),
            IconButton(
                onPressed: onInfo,
                tooltip: '聊天信息',
                icon: const Icon(Icons.more_horiz_rounded,
                    size: 24, color: ChatScene.ink)),
          ])));
}

class _RecommendationRows extends StatelessWidget {
  const _RecommendationRows({
    required this.items,
    required this.onSelected,
  });

  final List<String> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('为您推荐',
            style: TextStyle(fontSize: 10, color: ChatScene.muted)),
        const SizedBox(height: 6),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final item in items)
                Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                            onTap: () => onSelected(item),
                            borderRadius: BorderRadius.circular(18),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Text(item,
                                    maxLines: 1,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: ChatScene.muted))))))
            ]))
      ]));
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat(
      {this.assistantRole, this.onAvatarTap, this.onAvatarLongPress});
  final VoidCallback? onAvatarTap, onAvatarLongPress;

  final String? assistantRole;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -.15),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              key: const ValueKey('empty-chat-avatar'),
              dimension: 104,
              child: Center(
                child: ChatPortrait(
                    size: 88,
                    onTap: onAvatarTap,
                    onLongPress: onAvatarLongPress,
                    child: AssistantAvatar(role: assistantRole, size: 88)),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              '今天想聊点什么？',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
