import 'dart:async';
import 'package:bingo/core/device/device_tool_executor.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/local_chat_store.dart';
import 'package:bingo/features/chat/data/companion_store.dart';
import 'package:bingo/features/chat/data/reply_audio_player.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/models/assistant_segments.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:flutter/foundation.dart';

enum ChatStatus { idle, sending, failed }

class ChatController extends ChangeNotifier {
  ChatController({
    required ChatGateway gateway,
    DeviceActionGateway? deviceActions,
    DeviceToolExecutor? deviceToolExecutor,
    LocalChatStore? localStore,
    ConversationGateway? remoteHistory,
    EngagementGateway? engagement,
  })  : _gateway = gateway,
        _deviceActions = deviceActions,
        _deviceToolExecutor = deviceToolExecutor,
        _localStore = localStore,
        _remoteHistory = remoteHistory,
        _engagement = engagement;

  final ChatGateway _gateway;
  final _replyAudio = ReplyAudioPlayer();
  final _companionStore = CompanionStore();
  bool _readAloudEnabled = false;
  bool _speechActive = false;
  bool _acceptAudio = false;
  String? _speechError;
  bool get readAloudEnabled => _readAloudEnabled;
  double lastAudioSeconds = 0;
  DateTime? lastAudioStartedAt;
  String? get speechError => _speechError;
  String? get userId => _userId;

  Future<void> activateSpeech() async {
    _speechActive = true;
    final userId = _userId;
    if (userId == null) return;
    dynamic enabled;
    try {
      enabled = await _companionStore.read(userId, 'read_aloud');
    } catch (_) {
      enabled = false;
    }
    if (_userId != userId || !_speechActive) return;
    _readAloudEnabled = enabled == true;
    _updateSpeechGateway();
    notifyListeners();
  }

  void _updateSpeechGateway() {
    if (_gateway case final ReplySpeechGateway gateway) {
      gateway.readAloud = _readAloudEnabled && _speechActive;
    }
  }

  Future<void> setReadAloud(bool enabled) async {
    _readAloudEnabled = enabled;
    _speechError = null;
    _updateSpeechGateway();
    if (!enabled) await stopSpeech();
    notifyListeners();
    final userId = _userId;
    if (userId != null) {
      try {
        await _companionStore.write(userId, 'read_aloud', enabled);
      } catch (_) {
        _speechError = '朗读偏好未能保存，本次仍可使用';
        notifyListeners();
      }
    }
  }

  void deactivateSpeech() {
    _speechActive = false;
    _updateSpeechGateway();
    unawaited(stopSpeech());
  }

  Future<void> stopSpeech() async {
    _acceptAudio = false;
    await _replyAudio.stop();
    if (_gateway case final ReplySpeechGateway gateway) {
      unawaited(gateway.stopReplySpeech());
    }
  }

  final DeviceActionGateway? _deviceActions;
  final DeviceToolExecutor? _deviceToolExecutor;
  final LocalChatStore? _localStore;
  final ConversationGateway? _remoteHistory;
  final EngagementGateway? _engagement;
  final List<ChatMessage> _messages = [];
  final List<DeviceAction> _deviceActionItems = [];
  final List<Object> _timelineItems = [];
  final List<DeviceAction> _pendingTimelineActions = [];
  String? _conversationId;
  ChatStatus _status = ChatStatus.idle;
  String? _errorMessage;
  String? _userId;
  String? _title;
  bool _refreshingEngagement = false;
  bool _syncingRemote = false;
  bool _roleConversation = false;
  bool _accountOnly = false;
  int _bindingSequence = 0;
  String? _assistantRole;
  final List<String> _recommendations = [];
  int _runSequence = 0;
  String? _activeRunId;
  String? _attachedRunId;
  IncomingCallInvitation? _incomingCall;
  Timer? _recoveryTimer;
  int _recoveryAttempts = 0;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<DeviceAction> get deviceActions => List.unmodifiable(_deviceActionItems);
  List<Object> get timelineItems => List.unmodifiable(_timelineItems);
  ChatStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isBusy => _status == ChatStatus.sending;
  List<String> get recommendations => List.unmodifiable(_recommendations);
  String? get conversationId => _conversationId;

  IncomingCallInvitation? takeIncomingCall() {
    final invitation = _incomingCall;
    _incomingCall = null;
    return invitation;
  }

  Future<void> reloadConversation(String conversationId) async {
    final gateway = _remoteHistory;
    if (gateway == null) {
      return;
    }
    final binding = _bindingSequence;
    try {
      final messages = await gateway.listMessages(conversationId);
      if (binding != _bindingSequence ||
          (_roleConversation && conversationId != _conversationId)) {
        return;
      }
      _conversationId = conversationId;
      _messages
        ..clear()
        ..addAll(_expandAssistantMessages(messages));
      _timelineItems
        ..clear()
        ..addAll(_expandTimelineItems(messages));
      _deviceActionItems
        ..clear()
        ..addAll(_timelineItems.whereType<DeviceAction>());
      _title = messages
          .where((message) => message.role == ChatRole.user)
          .map((message) => message.content)
          .firstOrNull;
      await _persist();
      notifyListeners();
    } catch (_) {
      // The persisted call transcript will be restored on the next refresh.
    }
  }

  void setAssistantRole(String? role) {
    _assistantRole = role;
  }

  Future<void> bindAccount(String userId) async {
    unbindUser();
    _userId = userId;
    _accountOnly = true;
    await _refreshPendingCall();
    await refreshEngagement();
    notifyListeners();
  }

  Future<void> bindConversation(
      String userId, String conversationId, String role) async {
    unbindUser();
    _userId = userId;
    _roleConversation = true;
    _assistantRole = role;
    _conversationId = conversationId;
    try {
      final conversation = await _localStore?.loadConversation(
          '$userId:conversation:$conversationId', conversationId);
      if (conversation != null) {
        _title = conversation.title;
        _messages.addAll(_expandAssistantMessages(conversation.messages));
        _timelineItems.addAll(_expandTimelineItems(conversation.timelineItems));
        _deviceActionItems
            .addAll(conversation.timelineItems.whereType<DeviceAction>());
      }
    } on Exception {
      _messages.clear();
      _timelineItems.clear();
    }
    await reloadConversation(conversationId);
    await refreshEngagement();
    notifyListeners();
  }

  Future<void> bindUser(String userId) async {
    _userId = userId;
    _conversationId = null;
    _title = null;
    _messages.clear();
    _deviceActionItems.clear();
    _timelineItems.clear();
    _pendingTimelineActions.clear();
    _recommendations.clear();
    _incomingCall = null;
    final store = _localStore;
    if (store == null) {
      await _refreshPendingCall();
      notifyListeners();
      return;
    }
    try {
      var localItems = await store.listConversations(userId);
      if (localItems.isEmpty && _remoteHistory != null) {
        final remoteItems = await _remoteHistory.listConversations();
        if (remoteItems.isNotEmpty) {
          final item = remoteItems.first;
          final remoteMessages = await _remoteHistory.listMessages(item.id);
          final messages =
              _expandAssistantMessages(remoteMessages).toList(growable: false);
          await store.saveConversation(
            userId: userId,
            conversationId: item.id,
            title: item.title,
            messages: messages,
            timelineItems: _expandTimelineItems(remoteMessages).toList(),
            updatedAt: item.createdAt,
          );
          await store.setActive(userId, item.id);
        }
        localItems = await store.listConversations(userId);
      }
      final conversation = await store.loadActive(userId) ??
          (localItems.isEmpty
              ? null
              : await store.loadConversation(userId, localItems.first.id));
      if (conversation != null) {
        _conversationId = conversation.id;
        _title = conversation.title;
        _messages
          ..clear()
          ..addAll(_expandAssistantMessages(conversation.messages));
        _timelineItems.addAll(_expandTimelineItems(conversation.timelineItems));
        _deviceActionItems.addAll(
          conversation.timelineItems.whereType<DeviceAction>(),
        );
        await _persist();
      }
    } catch (_) {
      // Local history must never prevent sign-in or chatting.
    }
    await syncActiveConversation();
    await _refreshPendingCall();
    notifyListeners();
    await refreshEngagement();
  }

  Future<void> _refreshPendingCall() async {
    if (_gateway is! CallInvitationGateway) return;
    final gateway = _gateway as CallInvitationGateway;
    try {
      _incomingCall = await gateway.getPendingCallInvitation();
    } catch (_) {
      // An unavailable pending-call check must not block normal chat startup.
    }
  }

  void unbindUser() {
    deactivateSpeech();
    _readAloudEnabled = false;
    _bindingSequence++;
    _stopRecoveryPolling();
    _runSequence++;
    _activeRunId = null;
    _attachedRunId = null;
    _userId = null;
    _roleConversation = false;
    _accountOnly = false;
    _conversationId = null;
    _title = null;
    _messages.clear();
    _deviceActionItems.clear();
    _timelineItems.clear();
    _pendingTimelineActions.clear();
    _recommendations.clear();
    _incomingCall = null;
    _status = ChatStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  void dismissError() {
    _errorMessage = null;
    if (_status == ChatStatus.failed) _status = ChatStatus.idle;
    notifyListeners();
  }

  Future<void> sendImage(
    Uint8List bytes, {
    required String mimeType,
    String content = '',
  }) async {
    if (bytes.isEmpty) return;
    await _sendMessage(
      content.trim(),
      image: ChatImageUpload(bytes: bytes, mimeType: mimeType),
    );
  }

  Future<void> sendLocation(ChatLocation location) async {
    if (_gateway is! LocationGateway) {
      _errorMessage = '当前连接不支持发送位置';
      notifyListeners();
      return;
    }
    await _sendMessage('', location: location);
  }

  Future<void> send(String rawContent) async {
    final content = rawContent.trim();
    await _sendMessage(content);
  }

  Future<void> sendSpoken(String content) =>
      _sendMessage(content.trim(), spoken: true);

  MomentGateway? get momentGateway =>
      _gateway is MomentGateway ? _gateway as MomentGateway : null;

  Future<void> sendMomentSummary(
      String feature, String summary, String sessionId) async {
    if (_messages.any((message) =>
        message.runId == sessionId &&
        message.role == ChatRole.assistant &&
        message.status == ChatMessageStatus.completed)) {
      return;
    }
    if (momentGateway == null || _conversationId == null) {
      throw StateError('陪伴功能暂不可用');
    }
    await _sendMessage('[$feature] $summary',
        momentFeature: feature,
        momentSummary: summary,
        momentSessionId: sessionId);
  }

  Future<void> _sendMessage(
    String content, {
    ChatImageUpload? image,
    ChatLocation? location,
    bool spoken = false,
    String? momentFeature,
    String? momentSummary,
    String? momentSessionId,
  }) async {
    if (content.isEmpty && image == null && location == null) return;
    await stopSpeech();
    _acceptAudio = (spoken || _readAloudEnabled) && _speechActive;
    lastAudioSeconds = 0;
    lastAudioStartedAt = null;
    if (_gateway case final ReplySpeechGateway gateway) {
      gateway.readAloud = _acceptAudio;
    }
    _speechError = null;

    final supersededRunId = _activeRunId;
    if (supersededRunId != null) {
      _markRunInterrupted(supersededRunId);
    }
    final generation = ++_runSequence;
    final runId = momentSessionId ??
        'mobile-${DateTime.now().microsecondsSinceEpoch}-$generation';
    _activeRunId = runId;
    _attachedRunId = runId;

    if (_recommendations.isNotEmpty) {
      _recommendations.clear();
      notifyListeners();
      unawaited(_clearRecommendations());
    }

    final createdAt = DateTime.now();
    final timestamp = createdAt.microsecondsSinceEpoch;
    final existingMomentIndex = momentSessionId == null
        ? -1
        : _messages.indexWhere((message) =>
            message.runId == momentSessionId && message.role == ChatRole.user);
    final userMessageIndex =
        existingMomentIndex < 0 ? _messages.length : existingMomentIndex;
    final displayedContent = location != null
        ? '[位置] ${location.name}：${location.address}'
        : content.isEmpty
            ? '[图片]'
            : content;
    _title ??= displayedContent.length > 80
        ? displayedContent.substring(0, 80)
        : displayedContent;
    if (existingMomentIndex < 0) {
      _addMessage(
        ChatMessage(
          id: 'local-user-$timestamp',
          role: ChatRole.user,
          content: displayedContent,
          imageBytes: image?.bytes,
          type: location == null
              ? ChatMessageType.chat
              : ChatMessageType.location,
          location: location,
          createdAt: createdAt,
          runId: runId,
        ),
      );
    }
    final assistantMessageStartIndex = _messages.length;
    _status = ChatStatus.sending;
    _errorMessage = null;
    notifyListeners();
    await _persist();

    try {
      var segmentIndex = 0;
      final events = momentFeature != null
          ? momentGateway!.finishMoment(
              conversationId: _conversationId!,
              sessionId: momentSessionId!,
              feature: momentFeature,
              summary: momentSummary!)
          : location != null
              ? (_gateway as LocationGateway).sendLocation(
                  conversationId: _conversationId,
                  location: location,
                  runId: runId,
                  supersedesRunId: supersededRunId)
              : _gateway.send(
                  conversationId: _conversationId,
                  content: content,
                  runId: runId,
                  supersedesRunId: supersededRunId,
                  images: image == null ? const [] : [image],
                );
      await for (final event in events) {
        if (generation != _runSequence) continue;
        switch (event) {
          case ChatAudio():
            lastAudioSeconds += event.bytes.length / 48000;
            if (_acceptAudio && _speechActive) {
              try {
                await _replyAudio.add(event.bytes);
                lastAudioStartedAt ??= DateTime.now();
              } catch (_) {
                _speechError = '朗读播放失败，文字回复不受影响';
                await stopSpeech();
              }
            }
          case ChatAudioDone():
            if (_acceptAudio) {
              try {
                await _replyAudio.finish();
              } catch (_) {
                await stopSpeech();
              }
            }
          case ChatAudioError():
            _speechError = event.message;
            await stopSpeech();
          case ChatStarted():
            _conversationId = event.conversationId;
            if (event.userMessageId != null && event.createdAt != null) {
              _replaceMessageAt(
                userMessageIndex,
                _messages[userMessageIndex].copyWith(
                  id: event.userMessageId,
                  imageId: event.imageId,
                  createdAt: event.createdAt,
                ),
              );
            }
            await _persist();
          case ChatSegment():
            final message = ChatMessage(
              id: 'segment-$timestamp-${segmentIndex++}',
              role: ChatRole.assistant,
              content: event.content,
              createdAt: DateTime.now(),
              assistantRole: _assistantRole,
              runId: runId,
              status: ChatMessageStatus.streaming,
            );
            _addMessage(message);
            await _persist();
          case ChatFinished():
            final lastAssistantIndex = _messages.length - 1;
            for (var index = assistantMessageStartIndex;
                index <= lastAssistantIndex;
                index++) {
              final message = _messages[index];
              if (message.role != ChatRole.assistant) continue;
              _replaceMessageAt(
                index,
                message.copyWith(
                  id: index == lastAssistantIndex ? event.messageId : null,
                  createdAt: event.createdAt,
                  assistantRole: event.assistantRole,
                  status: ChatMessageStatus.completed,
                ),
              );
            }
            _timelineItems.addAll(_pendingTimelineActions);
            _pendingTimelineActions.clear();
            _status = ChatStatus.idle;
            _activeRunId = null;
            await _persist();
          case ChatApprovalRequired():
            _deviceActionItems.add(event.action);
            _pendingTimelineActions.add(event.action);
          case ChatIncomingCall():
            await stopSpeech();
            _incomingCall = event.invitation;
          case ChatInterrupted():
            await stopSpeech();
            _markRunInterrupted(event.runId);
            _status = ChatStatus.idle;
            _activeRunId = null;
            await _persist();
        }
        notifyListeners();
      }
      if (generation == _runSequence && isBusy) {
        throw const FormatException('响应未正常结束');
      }
    } catch (_) {
      if (generation != _runSequence) return;
      _timelineItems.addAll(_pendingTimelineActions);
      _pendingTimelineActions.clear();
      _status = ChatStatus.failed;
      _activeRunId = null;
      _errorMessage = '无法连接到服务端，请检查地址、网络和服务状态。';
      await _persist();
      _startRecoveryPolling();
      notifyListeners();
    } finally {
      if (_attachedRunId == runId) _attachedRunId = null;
    }
  }

  Future<void> syncActiveConversation() async {
    final gateway = _remoteHistory;
    final conversationId = _conversationId;
    if (gateway == null ||
        conversationId == null ||
        _syncingRemote ||
        _attachedRunId != null) {
      return;
    }
    _syncingRemote = true;
    final binding = _bindingSequence;
    try {
      await _reportPendingActions();
      final remoteMessages = await gateway.listMessages(conversationId);
      if (binding != _bindingSequence) return;
      final pendingRunId = _unfinishedRunId();
      final remoteFinished = pendingRunId == null ||
          remoteMessages.any(
            (message) =>
                message.role == ChatRole.assistant &&
                message.runId == pendingRunId &&
                message.status != ChatMessageStatus.streaming,
          );
      if (!remoteFinished) {
        _activeRunId = pendingRunId;
        _status = ChatStatus.sending;
        _startRecoveryPolling();
        notifyListeners();
        return;
      }
      if (remoteMessages.isEmpty) return;
      _messages
        ..clear()
        ..addAll(_expandAssistantMessages(remoteMessages));
      final previousActions = _timelineItems.indexed
          .where((entry) => entry.$2 is DeviceAction)
          .map((entry) => (entry.$1, entry.$2 as DeviceAction))
          .toList();
      _timelineItems
        ..clear()
        ..addAll(_expandTimelineItems(remoteMessages));
      for (final (index, action) in previousActions) {
        final remoteIndex = _timelineItems
            .indexWhere((item) => item is DeviceAction && item.id == action.id);
        if (remoteIndex < 0) {
          _timelineItems.insert(index.clamp(0, _timelineItems.length), action);
        } else if ({'report_pending', 'failure_report_pending', 'processing'}
                .contains(action.status) &&
            {
              'pending',
              'approved'
            }.contains((_timelineItems[remoteIndex] as DeviceAction).status)) {
          _timelineItems[remoteIndex] = action;
        }
      }
      _deviceActionItems
        ..clear()
        ..addAll(_timelineItems.whereType<DeviceAction>());
      _title = remoteMessages
          .where((message) => message.role == ChatRole.user)
          .map((message) => message.content)
          .firstOrNull;
      _activeRunId = null;
      _status = ChatStatus.idle;
      _errorMessage = null;
      _stopRecoveryPolling();
      await _persist();
      notifyListeners();
    } on Exception {
      if (_unfinishedRunId() != null) _startRecoveryPolling();
    } finally {
      _syncingRemote = false;
    }
  }

  String? _unfinishedRunId() {
    for (final message in _messages.reversed) {
      if (message.role != ChatRole.user || message.runId == null) continue;
      final replies = _messages.where(
        (candidate) =>
            candidate.role == ChatRole.assistant &&
            candidate.runId == message.runId,
      );
      if (replies.isEmpty ||
          replies.any(
            (candidate) => candidate.status == ChatMessageStatus.streaming,
          )) {
        return message.runId;
      }
      return null;
    }
    return null;
  }

  void _startRecoveryPolling() {
    if (_recoveryTimer != null || _unfinishedRunId() == null) return;
    _recoveryAttempts = 0;
    _recoveryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _recoveryAttempts++;
      if (_recoveryAttempts >= 60 || _unfinishedRunId() == null) {
        _stopRecoveryPolling();
        return;
      }
      unawaited(syncActiveConversation());
    });
  }

  void _stopRecoveryPolling() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _recoveryAttempts = 0;
  }

  void _markRunInterrupted(String runId) {
    final matchingIndexes = <int>[];
    for (var index = 0; index < _messages.length; index++) {
      final message = _messages[index];
      if (message.role == ChatRole.assistant &&
          message.runId == runId &&
          message.status == ChatMessageStatus.streaming) {
        matchingIndexes.add(index);
      }
    }
    for (final index in matchingIndexes) {
      _replaceMessageAt(
        index,
        _messages[index].copyWith(
          status: index == matchingIndexes.last
              ? ChatMessageStatus.interrupted
              : ChatMessageStatus.completed,
        ),
      );
    }
    _timelineItems.addAll(_pendingTimelineActions);
    _pendingTimelineActions.clear();
  }

  Future<void> sendRecommendation(String content) async {
    _recommendations.clear();
    notifyListeners();
    await _clearRecommendations();
    await send(content);
  }

  Future<void> _clearRecommendations() async {
    try {
      if (_roleConversation &&
          _gateway is RoleConversationGateway &&
          _conversationId != null) {
        await (_gateway as RoleConversationGateway)
            .clearConversationRecommendations(_conversationId!);
      } else {
        await _engagement?.clearRecommendations();
      }
    } on Exception {
      // The next activity also invalidates server-side recommendations.
    }
  }

  Future<void> refreshEngagement() async {
    final gateway = _engagement;
    final store = _localStore;
    final userId = _userId;
    if (gateway == null ||
        store == null ||
        userId == null ||
        _refreshingEngagement) {
      return;
    }
    _refreshingEngagement = true;
    final binding = _bindingSequence;
    final conversationId = _conversationId;
    try {
      await _refreshPendingCall();
      final proactive = await gateway.listProactiveMessages();
      for (final item in proactive) {
        final saved = await _saveProactiveMessage(store, userId, item);
        if (saved) await gateway.acknowledgeProactiveMessage(item.id);
      }
      final recommendations = _accountOnly
          ? <String>[]
          : _roleConversation &&
                  _gateway is RoleConversationGateway &&
                  conversationId != null
              ? await (_gateway as RoleConversationGateway)
                  .getConversationRecommendations(conversationId)
              : await gateway.getRecommendations();
      if (binding != _bindingSequence) return;
      _recommendations
        ..clear()
        ..addAll(recommendations.take(3));
      notifyListeners();
    } on Exception {
      // Engagement sync is best-effort and must not interrupt chat.
    } finally {
      _refreshingEngagement = false;
    }
  }

  Future<bool> _saveProactiveMessage(
    LocalChatStore store,
    String userId,
    ProactiveMessage proactive,
  ) async {
    try {
      if (_conversationId == proactive.conversationId) {
        if (_messages.any((message) => message.id == proactive.messageId)) {
          return true;
        }
        _addMessage(ChatMessage(
          id: proactive.messageId,
          role: ChatRole.assistant,
          content: proactive.content,
          createdAt: proactive.createdAt,
          assistantRole: proactive.assistantRole ?? _assistantRole,
        ));
        return await _persist();
      }

      var conversation =
          await store.loadConversation(userId, proactive.conversationId);
      if (conversation == null && _remoteHistory != null) {
        final messages =
            await _remoteHistory.listMessages(proactive.conversationId);
        conversation = LocalConversation(
          id: proactive.conversationId,
          title: proactive.content,
          messages: messages,
        );
      }
      if (conversation == null) return false;
      if (conversation.messages
          .any((message) => message.id == proactive.messageId)) {
        return true;
      }
      final message = ChatMessage(
        id: proactive.messageId,
        role: ChatRole.assistant,
        content: proactive.content,
        createdAt: proactive.createdAt,
        assistantRole: proactive.assistantRole ?? _assistantRole,
      );
      await store.saveConversation(
        userId: userId,
        conversationId: conversation.id,
        title: conversation.title,
        messages: [...conversation.messages, message],
        timelineItems: [...conversation.timelineItems, message],
        updatedAt: proactive.createdAt,
      );
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> approveDeviceAction(DeviceAction action) async {
    final gateway = _deviceActions;
    final executor = _deviceToolExecutor;
    if (gateway == null ||
        executor == null ||
        !{'pending', 'failed'}.contains(_deviceActionItems
            .where((item) => item.id == action.id)
            .firstOrNull
            ?.status)) {
      return;
    }

    _replaceAction(action.copyWith(status: 'processing'));
    var approvedOnServer = false;
    String? executionResult;
    try {
      final approved = await gateway.approveDeviceAction(action.id);
      approvedOnServer = true;
      executionResult =
          await executor.execute(approved.tool, approved.arguments);
      final completed = await gateway.completeDeviceAction(
        action.id,
        succeeded: true,
        result: executionResult,
      );
      _replaceAction(action.copyWith(
          status: completed.status,
          result: completed.result ?? executionResult));
    } on Exception catch (error) {
      if (executionResult != null) {
        _replaceAction(
            action.copyWith(status: 'report_pending', result: executionResult));
        _errorMessage = '设备操作已执行，但结果同步失败，将在连接恢复后同步，请勿重复创建。';
      } else if (approvedOnServer) {
        try {
          await gateway.completeDeviceAction(
            action.id,
            succeeded: false,
            result: error.toString(),
          );
        } on Exception {
          _replaceAction(action.copyWith(
              status: 'failure_report_pending', result: error.toString()));
        }
        if (_deviceActionItems.any(
            (item) => item.id == action.id && item.status == 'processing')) {
          _replaceAction(
              action.copyWith(status: 'failed', result: error.toString()));
        }
        _errorMessage = '无法执行设备操作：$error';
      } else {
        _replaceAction(action.copyWith(status: action.status));
        _errorMessage = '确认失败，请检查服务连接。';
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> rejectDeviceAction(DeviceAction action) async {
    final gateway = _deviceActions;
    if (gateway == null ||
        _deviceActionItems
                .where((item) => item.id == action.id)
                .firstOrNull
                ?.status !=
            'pending') {
      return;
    }
    _replaceAction(action.copyWith(status: 'processing'));
    try {
      await gateway.rejectDeviceAction(action.id);
      _replaceAction(action.copyWith(status: 'rejected'));
    } on Exception {
      _replaceAction(action.copyWith(status: 'pending'));
      _errorMessage = '拒绝操作失败，请检查服务连接。';
    }
    await _persist();
    notifyListeners();
  }

  void _replaceAction(DeviceAction updated) {
    final index =
        _deviceActionItems.indexWhere((item) => item.id == updated.id);
    if (index >= 0) {
      _deviceActionItems[index] = updated;
    }
    final timelineIndex = _timelineItems.indexWhere(
      (item) => item is DeviceAction && item.id == updated.id,
    );
    if (timelineIndex >= 0) {
      _timelineItems[timelineIndex] = updated;
    }
    final pendingIndex = _pendingTimelineActions.indexWhere(
      (item) => item.id == updated.id,
    );
    if (pendingIndex >= 0) {
      _pendingTimelineActions[pendingIndex] = updated;
    }
    notifyListeners();
  }

  Future<void> _reportPendingActions() async {
    final gateway = _deviceActions;
    if (gateway == null) {
      return;
    }
    for (final action in List<DeviceAction>.of(_deviceActionItems)) {
      if (!{'report_pending', 'failure_report_pending'}
          .contains(action.status)) {
        continue;
      }
      try {
        final completed = await gateway.completeDeviceAction(action.id,
            succeeded: action.status == 'report_pending',
            result: action.result);
        _replaceAction(action.copyWith(
            status: completed.status, result: completed.result));
      } on Exception {
        continue;
      }
    }
  }

  void _addMessage(ChatMessage message) {
    _messages.add(message);
    _timelineItems.add(message);
  }

  Iterable<ChatMessage> _expandAssistantMessages(
    Iterable<ChatMessage> messages,
  ) sync* {
    for (final message in messages) {
      if (message.deviceAction != null) {
        continue;
      }
      yield* _expandAssistantMessage(_withAssistantRoleSnapshot(message));
    }
  }

  Iterable<Object> _expandTimelineItems(Iterable<Object> items) sync* {
    for (final item in items) {
      if (item is ChatMessage) {
        if (item.deviceAction != null) {
          yield DeviceAction.fromJson(item.deviceAction!);
        } else {
          yield* _expandAssistantMessage(_withAssistantRoleSnapshot(item));
        }
      } else {
        yield item;
      }
    }
  }

  Iterable<ChatMessage> _expandAssistantMessage(ChatMessage message) sync* {
    if (message.role != ChatRole.assistant ||
        message.type != ChatMessageType.chat) {
      yield message;
      return;
    }
    final segments = splitAssistantBubbles(message.content);
    if (segments.length <= 1) {
      yield message;
      return;
    }
    for (var index = 0; index < segments.length; index++) {
      final isLast = index == segments.length - 1;
      yield message.copyWith(
        id: isLast ? message.id : '${message.id}:segment:$index',
        content: segments[index],
        status: isLast ? message.status : ChatMessageStatus.completed,
      );
    }
  }

  ChatMessage _withAssistantRoleSnapshot(ChatMessage message) {
    if (message.role != ChatRole.assistant || message.assistantRole != null) {
      return message;
    }
    return message.copyWith(assistantRole: _assistantRole);
  }

  void _replaceMessageAt(int messageIndex, ChatMessage replacement) {
    final previous = _messages[messageIndex];
    _messages[messageIndex] = replacement;
    final timelineIndex = _timelineItems.lastIndexWhere(
      (item) => item is ChatMessage && item.id == previous.id,
    );
    if (timelineIndex >= 0) {
      _timelineItems[timelineIndex] = replacement;
    }
  }

  Future<bool> _persist() async {
    final store = _localStore;
    final userId = _userId;
    final conversationId = _conversationId;
    if (store == null || userId == null || conversationId == null) return false;
    try {
      await store.saveConversation(
        userId:
            _roleConversation ? '$userId:conversation:$conversationId' : userId,
        conversationId: conversationId,
        title: _title ?? '新对话',
        messages: List.of(_messages),
        timelineItems: List.of(_timelineItems),
      );
      return true;
    } catch (_) {
      // Chat remains usable if the device database is temporarily unavailable.
      return false;
    }
  }

  @override
  void dispose() {
    deactivateSpeech();
    _stopRecoveryPolling();
    super.dispose();
  }
}
