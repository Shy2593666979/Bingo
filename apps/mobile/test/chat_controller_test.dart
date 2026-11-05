import 'dart:async';

import 'package:bingo/core/device/device_tool_executor.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/local_chat_store.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/features/chat/presentation/chat_page.dart';
import 'package:bingo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeechGateway implements SpeechGateway {
  @override
  Future<String> transcribe(Uint8List wavAudio) async => '测试语音';
}

class FakeChatGateway implements ChatGateway {
  static final userCreatedAt = DateTime.utc(2026, 9, 25, 4, 40);
  static final assistantCreatedAt = DateTime.utc(2026, 9, 25, 4, 41);
  String? lastContent;
  List<ChatImageUpload> lastImages = const [];

  @override
  Stream<ChatStreamEvent> send({
    String? conversationId,
    required String content,
    required String runId,
    String? supersedesRunId,
    List<ChatImageUpload> images = const [],
  }) async* {
    lastContent = content;
    lastImages = images;
    yield ChatStarted(
      'conversation-1',
      userMessageId: 'user-message-1',
      imageId: images.isEmpty ? null : 'image-1',
      createdAt: userCreatedAt,
    );
    yield const ChatSegment('第一句。');
    yield const ChatSegment('第二句！');
    yield ChatFinished(
      'message-1',
      createdAt: assistantCreatedAt,
      assistantRole: 'teacher',
    );
  }
}

class SegmentedSpeechGateway implements ChatGateway, ReplySpeechGateway {
  @override
  bool readAloud = false;

  @override
  Future<void> stopReplySpeech() async {}

  @override
  Stream<ChatStreamEvent> send({
    String? conversationId,
    required String content,
    required String runId,
    String? supersedesRunId,
    List<ChatImageUpload> images = const [],
  }) async* {
    yield const ChatStarted('conversation-1');
    yield const ChatSegment('早呀', segmentIndex: 0);
    yield ChatAudio(Uint8List.fromList([1, 0]), segmentIndex: 0);
    yield const ChatAudioSegmentDone(0);
    yield const ChatSegment('昨晚睡得怎么样？', segmentIndex: 1);
    yield ChatAudio(Uint8List.fromList([2, 0]), segmentIndex: 1);
    yield const ChatAudioSegmentDone(1);
    yield const ChatFinished('message-1');
    yield const ChatAudioDone();
  }
}

class IncomingCallChatGateway implements ChatGateway {
  static final invitation = IncomingCallInvitation(
    id: 'call-1',
    conversationId: 'conversation-1',
    callerName: 'Bingo',
    callerRole: '男朋友',
    reason: '想听听你的声音',
    expiresAt: DateTime.now().add(const Duration(seconds: 30)),
  );

  @override
  Stream<ChatStreamEvent> send({
    String? conversationId,
    required String content,
    required String runId,
    String? supersedesRunId,
    List<ChatImageUpload> images = const [],
  }) async* {
    yield const ChatStarted('conversation-1');
    yield ChatIncomingCall(invitation);
    yield const ChatSegment('我给你打过来啦。');
    yield const ChatFinished('message-1');
  }
}

class FakeApprovalGateway implements ChatGateway, DeviceActionGateway {
  var approved = false;
  var completed = false;
  var sendCount = 0;
  var completionFailures = 0;

  static const action = DeviceAction(
    id: 'action-1',
    tool: 'device_alarm_create',
    title: '创建闹钟',
    description: '2099-01-01 07:00 · 起床',
    arguments: {
      'scheduled_at': '2099-01-01T07:00:00+08:00',
      'label': '起床',
      'recurrence': 'none',
    },
  );

  @override
  Stream<ChatStreamEvent> send({
    String? conversationId,
    required String content,
    required String runId,
    String? supersedesRunId,
    List<ChatImageUpload> images = const [],
  }) async* {
    yield const ChatStarted('conversation-1');
    if (sendCount++ == 0) {
      yield const ChatApprovalRequired(action);
      yield const ChatSegment('等待确认。');
      yield const ChatFinished('message-1');
    } else {
      yield const ChatSegment('后续回复。');
      yield const ChatFinished('message-2');
    }
  }

  @override
  Future<DeviceAction> approveDeviceAction(String actionId) async {
    approved = true;
    return action.copyWith(status: 'approved');
  }

  @override
  Future<DeviceAction> completeDeviceAction(
    String actionId, {
    required bool succeeded,
    String? result,
  }) async {
    if (completionFailures > 0) {
      completionFailures--;
      throw Exception('offline');
    }
    completed = true;
    return action.copyWith(status: succeeded ? 'succeeded' : 'failed');
  }

  @override
  Future<void> rejectDeviceAction(String actionId) async {}
}

class InterruptibleChatGateway implements ChatGateway {
  final List<({String runId, String? supersedesRunId, String content})> calls =
      [];
  final Map<String, StreamController<ChatStreamEvent>> streams = {};

  @override
  Stream<ChatStreamEvent> send({
    String? conversationId,
    required String content,
    required String runId,
    String? supersedesRunId,
    List<ChatImageUpload> images = const [],
  }) {
    calls.add((
      runId: runId,
      supersedesRunId: supersedesRunId,
      content: content,
    ));
    final controller = StreamController<ChatStreamEvent>();
    streams[runId] = controller;
    return controller.stream;
  }
}

class FakeDeviceToolExecutor implements DeviceToolExecutor {
  var executed = false;

  @override
  Future<String> execute(String tool, Map<String, dynamic> arguments) async {
    executed = true;
    return 'opened';
  }
}

class FakeEngagementGateway implements EngagementGateway {
  FakeEngagementGateway({
    this.proactive = const [],
    this.recommendations = const [],
  });

  final List<ProactiveMessage> proactive;
  List<String> recommendations;
  final List<String> acknowledged = [];
  bool cleared = false;

  @override
  Future<void> acknowledgeProactiveMessage(String id) async {
    acknowledged.add(id);
  }

  @override
  Future<void> clearRecommendations() async {
    cleared = true;
    recommendations = [];
  }

  @override
  Future<List<String>> getRecommendations() async => recommendations;

  @override
  Future<List<ProactiveMessage>> listProactiveMessages() async => proactive;
}

class MemoryChatStore implements LocalChatStore {
  final Map<String, LocalConversation> conversations = {};
  String? activeId;

  @override
  Future<void> close() async {}

  @override
  Future<List<LocalConversationSummary>> listConversations(
      String userId) async {
    return conversations.values
        .map(
          (item) => LocalConversationSummary(
            id: item.id,
            title: item.title,
            updatedAt: DateTime(2026),
          ),
        )
        .toList();
  }

  @override
  Future<LocalConversation?> loadActive(String userId) async {
    return activeId == null ? null : conversations[activeId];
  }

  @override
  Future<LocalConversation?> loadConversation(
    String userId,
    String conversationId,
  ) async {
    return conversations[conversationId];
  }

  @override
  Future<void> saveConversation({
    required String userId,
    required String conversationId,
    required String title,
    required List<ChatMessage> messages,
    DateTime? updatedAt,
    List<Object>? timelineItems,
  }) async {
    conversations[conversationId] = LocalConversation(
      id: conversationId,
      title: title,
      messages: List.of(messages),
      timelineItems: timelineItems == null ? null : List.of(timelineItems),
    );
    activeId = conversationId;
  }

  @override
  Future<void> setActive(String userId, String? conversationId) async {
    activeId = conversationId;
  }
}

class RecoveringChatGateway implements ChatGateway, ConversationGateway {
  RecoveringChatGateway(this.remoteMessages);

  List<ChatMessage> remoteMessages;
  int loads = 0;

  @override
  Future<List<ConversationSummary>> listConversations() async => const [];

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    loads++;
    return List.of(remoteMessages);
  }

  @override
  Stream<ChatStreamEvent> send({
    String? conversationId,
    required String content,
    required String runId,
    String? supersedesRunId,
    List<ChatImageUpload> images = const [],
  }) =>
      const Stream.empty();
}

void main() {
  testWidgets(
      'pending AI welcome shows typing then reveals sentence bubbles gradually',
      (tester) async {
    for (final name in ['bingo/local_chat', 'bingo/device_tools']) {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null));
    }
    final gateway = RecoveringChatGateway([
      const ChatMessage(
          id: 'welcome',
          role: ChatRole.assistant,
          content: '',
          runId: 'welcome-job',
          status: ChatMessageStatus.streaming)
    ]);
    final controller = ChatController(gateway: gateway, remoteHistory: gateway);
    await controller.bindConversation('u', 'c', '女朋友', welcomeUnread: true);
    await controller.activateSpeech();
    expect(controller.messages, isEmpty);
    expect(controller.timelineItems, isEmpty);
    expect(controller.isWaitingForReply, isTrue);
    await tester.pump(const Duration(seconds: 130));
    controller.deactivateSpeech();
    final beforePause = gateway.loads;
    await tester.pump(const Duration(seconds: 10));
    expect(gateway.loads, greaterThan(beforePause));
    await controller.activateSpeech();
    gateway.remoteMessages = [
      const ChatMessage(
          id: 'welcome',
          role: ChatRole.assistant,
          content: '小雨，很高兴认识你。今天想聊些什么？',
          runId: 'welcome-job')
    ];
    await tester.pump(const Duration(seconds: 2));
    expect(controller.messages, hasLength(1));
    expect(controller.isWaitingForReply, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(controller.messages, hasLength(2));
    expect(controller.isWaitingForReply, isFalse);
    controller.dispose();
  });
  testWidgets('server welcome continues offscreen and is not replayed on entry',
      (tester) async {
    for (final name in ['bingo/local_chat', 'bingo/device_tools']) {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null));
    }
    final gateway = RecoveringChatGateway([
      const ChatMessage(
          id: 'first',
          role: ChatRole.assistant,
          content: '',
          runId: 'welcome-job',
          status: ChatMessageStatus.streaming)
    ]);
    final controller = ChatController(gateway: gateway, remoteHistory: gateway);
    await controller.bindConversation('u', 'c', '公司高管', welcomeUnread: true);
    controller.deactivateSpeech();
    gateway.remoteMessages = [
      const ChatMessage(
          id: 'first',
          role: ChatRole.assistant,
          content: '你好。',
          runId: 'welcome-segment-job'),
      const ChatMessage(
          id: 'second',
          role: ChatRole.assistant,
          content: '',
          runId: 'welcome-segment-job',
          status: ChatMessageStatus.streaming)
    ];
    await tester.pump(const Duration(seconds: 2));
    expect(controller.messages.map((m) => m.content), ['你好。']);
    final loads = gateway.loads;
    await tester.pump(const Duration(seconds: 2));
    expect(gateway.loads, greaterThan(loads));
    gateway.remoteMessages = [
      gateway.remoteMessages.first,
      const ChatMessage(
          id: 'second',
          role: ChatRole.assistant,
          content: '今天想聊什么？',
          runId: 'welcome-segment-job')
    ];
    await tester.pump(const Duration(seconds: 2));
    expect(controller.messages, hasLength(2));
    expect(controller.isBusy, isFalse);
    await controller.activateSpeech();
    expect(controller.messages, hasLength(2));
    expect(controller.isWaitingForReply, isFalse);
    controller.dispose();
  });

  testWidgets('speech defaults on and preserves a saved disabled preference',
      (tester) async {
    const local = MethodChannel('bingo/local_chat');
    String? preference;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            local,
            (call) async =>
                call.method == 'readCompanionData' ? preference : null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(local, null));
    final controller = ChatController(gateway: FakeChatGateway());
    await controller.bindAccount('voice-default-user');
    await controller.activateSpeech();
    expect(controller.readAloudEnabled, isTrue);
    controller.deactivateSpeech();
    preference = 'false';
    await controller.activateSpeech();
    expect(controller.readAloudEnabled, isFalse);
    controller.dispose();
    await tester.pump();
  });
  testWidgets(
      'H3 consecutive assistant bubbles share one portrait and content edge',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemoryChatStore();
    store.conversations['h3'] =
        LocalConversation(id: 'h3', title: '连贯对话', messages: [
      ChatMessage(
          id: 'one',
          role: ChatRole.assistant,
          content: '第一句',
          createdAt: DateTime.utc(2026, 11, 1, 12)),
      ChatMessage(
          id: 'two',
          role: ChatRole.assistant,
          content: '接着聊一句',
          createdAt: DateTime.utc(2026, 11, 1, 12, 0, 20)),
      ChatMessage(
          id: 'three',
          role: ChatRole.assistant,
          content: '过一会儿再聊',
          createdAt: DateTime.utc(2026, 11, 1, 12, 5)),
    ]);
    store.activeId = 'h3';
    final controller =
        ChatController(gateway: FakeChatGateway(), localStore: store);
    await controller.bindUser('h3-user');
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            controller: controller,
            assistantName: '甜甜',
            assistantRole: '女朋友',
            speechGateway: FakeSpeechGateway(),
            onStartCall: () {},
            onIncomingCall: (_) async {},
            onOpenSettings: () {})));
    await tester.pumpAndSettle();
    final bubbles =
        tester.widgetList<MessageBubble>(find.byType(MessageBubble)).toList();
    expect(bubbles.map((b) => b.showAvatar), [true, false, true]);
    expect(tester.getTopLeft(find.text('第一句')).dx,
        tester.getTopLeft(find.text('接着聊一句')).dx);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  test('does not create an alarm again when reporting its result fails',
      () async {
    final gateway = FakeApprovalGateway()..completionFailures = 1;
    final executor = FakeDeviceToolExecutor();
    final controller = ChatController(
        gateway: gateway, deviceActions: gateway, deviceToolExecutor: executor);
    await controller.send('明早叫我');
    final original = controller.deviceActions.single;
    await controller.approveDeviceAction(original);
    expect(controller.deviceActions.single.status, 'report_pending');
    expect(controller.deviceActions.single.result, isNotNull);
    expect(gateway.completed, isFalse);
    await controller.approveDeviceAction(original);
    expect(gateway.completed, isFalse);
    expect(controller.deviceActions.single.status, 'report_pending');
    controller.dispose();
  });
  test(
      'restores resolved alarm cards from server history without turning them into text',
      () async {
    final gateway = RecoveringChatGateway([
      const ChatMessage(
          id: 'user-message', role: ChatRole.user, content: '明早叫我'),
      ChatMessage.fromJson({
        'id': 'alarm-card',
        'role': 'user',
        'message_type': 'device_action',
        'content': '[闹钟操作记录] 用户已取消，未创建',
        'device_action': {
          'id': 'alarm-card',
          'tool': 'device_alarm_create',
          'title': '创建闹钟',
          'description': '明天 07:00 · 起床',
          'arguments': <String, dynamic>{},
          'status': 'rejected',
          'result': null,
        },
      }),
      const ChatMessage(
          id: 'answer-after-alarm',
          role: ChatRole.assistant,
          content: '今晚早点休息。'),
      const ChatMessage(
          id: 'next-user-message', role: ChatRole.user, content: '谢谢'),
    ]);
    final store = MemoryChatStore();
    final controller = ChatController(
        gateway: gateway, remoteHistory: gateway, localStore: store);
    await controller.bindUser('user-1');
    await controller.reloadConversation('conversation-1');
    expect(controller.messages, hasLength(3));
    expect(
        (controller.timelineItems[1] as ChatMessage).id, 'answer-after-alarm');
    expect(controller.timelineItems[2], isA<DeviceAction>());
    expect(
        (controller.timelineItems[3] as ChatMessage).id, 'next-user-message');
    expect(controller.timelineItems.whereType<DeviceAction>().single.status,
        'rejected');
    await controller.syncActiveConversation();
    expect(controller.timelineItems.whereType<DeviceAction>().single.status,
        'rejected');
    final restored = ChatController(gateway: gateway, localStore: store);
    await restored.bindUser('user-1');
    expect(restored.timelineItems.whereType<DeviceAction>().single.status,
        'rejected');
    controller.dispose();
    restored.dispose();
  });

  testWidgets('alarm status updates do not move the chat scroll position',
      (tester) async {
    final gateway = FakeApprovalGateway();
    final history = RecoveringChatGateway([
      for (var index = 0; index < 25; index++)
        ChatMessage(
            id: 'history-$index',
            role: ChatRole.assistant,
            content: '第 $index 条历史回复，今晚记得早点休息。'),
      ChatMessage.fromJson({
        'id': 'action-1',
        'role': 'user',
        'content': '闹钟操作',
        'device_action': {
          'id': 'action-1',
          'tool': 'device_alarm_create',
          'title': '创建闹钟',
          'description': FakeApprovalGateway.action.description,
          'arguments': FakeApprovalGateway.action.arguments,
          'status': 'pending',
        },
      }),
    ]);
    final controller = ChatController(
        gateway: gateway,
        deviceActions: gateway,
        deviceToolExecutor: FakeDeviceToolExecutor(),
        remoteHistory: history);
    await controller.reloadConversation('conversation-1');
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            controller: controller,
            assistantName: '甜甜',
            assistantRole: '女朋友',
            speechGateway: FakeSpeechGateway(),
            onStartCall: () {},
            onIncomingCall: (_) async {},
            onOpenSettings: () {})));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(100);
    await tester.pumpAndSettle();
    final before = list.controller!.offset;
    await controller.approveDeviceAction(controller.deviceActions.single);
    await tester.pumpAndSettle();
    expect(list.controller!.offset, closeTo(before, 1));
    expect(controller.deviceActions.single.status, 'succeeded');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test('history synchronization retains legacy local alarm cards', () async {
    final gateway = FakeApprovalGateway();
    final history = RecoveringChatGateway([
      const ChatMessage(
          id: 'server-user', role: ChatRole.user, content: '明早叫我'),
      const ChatMessage(
          id: 'server-answer', role: ChatRole.assistant, content: '等待确认。'),
    ]);
    final controller = ChatController(
        gateway: gateway,
        deviceActions: gateway,
        deviceToolExecutor: FakeDeviceToolExecutor(),
        remoteHistory: history);
    await controller.send('明早叫我');
    await controller.rejectDeviceAction(controller.deviceActions.single);
    await controller.syncActiveConversation();
    expect(controller.timelineItems.whereType<DeviceAction>().single.status,
        'rejected');
    controller.dispose();
  });

  testWidgets(
      'chat header opens chat info and keeps speech controls in settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ChatController(gateway: FakeChatGateway());
    var calls = 0;
    var backs = 0;
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            controller: controller,
            assistantName: '暖暖',
            assistantRole: '男朋友',
            speechGateway: FakeSpeechGateway(),
            onStartCall: () => calls++,
            onBack: () => backs++,
            onIncomingCall: (_) async {},
            onOpenSettings: () {})));
    await tester.pumpAndSettle();
    expect(find.text('陪伴中'), findsNothing);
    expect(tester.getCenter(find.byTooltip('返回角色')).dx,
        lessThan(tester.getCenter(find.text('暖暖')).dx));
    expect(find.byTooltip('查找聊天记录'), findsOneWidget);
    await tester.tap(find.byTooltip('聊天信息'));
    await tester.pumpAndSettle();
    expect(find.text('聊天信息'), findsOneWidget);
    await tester.tap(find.text('语音通话'));
    await tester.pumpAndSettle();
    expect(controller.readAloudEnabled, isTrue);
    await tester.tap(find.text('开启声音'));
    await tester.pumpAndSettle();
    expect(controller.readAloudEnabled, isFalse);
    await tester.tap(find.text('开启声音'));
    await tester.pumpAndSettle();
    expect(controller.readAloudEnabled, isTrue);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回角色'));
    expect(calls, 1);
    expect(backs, 1);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets('renders one call record with status and duration',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CallRecordTile(
            message: ChatMessage(
              id: 'call-1',
              role: ChatRole.assistant,
              type: ChatMessageType.call,
              content: '通话已结束',
              callStatus: 'ended',
              callDurationSeconds: 65,
            ),
          ),
        ),
      ),
    );

    expect(find.text('语音通话'), findsOneWidget);
    expect(find.text('通话已结束  01:05'), findsOneWidget);
    expect(find.byIcon(Icons.call_rounded), findsOneWidget);
  });

  test('maps assistant roles to the expected avatar assets', () {
    expect(assistantAvatarAsset('男朋友'), 'assets/images/boyfriend.png');
    expect(assistantAvatarAsset('女朋友'), 'assets/images/girlfriend.png');
    expect(assistantAvatarAsset('家长'), 'assets/images/parent.png');
    expect(assistantAvatarAsset('邻家大叔'), 'assets/images/parent.png');
    expect(assistantAvatarAsset('弟弟'), 'assets/images/child.png');
    expect(assistantAvatarAsset('老师'), 'assets/images/teacher.png');
    expect(assistantAvatarAsset('小孩'), 'assets/images/child.png');
    expect(assistantAvatarAsset('同事'), 'assets/images/colleague.png');
    expect(assistantAvatarAsset('生活助理'), 'assets/images/bingo_logo.png');
  });

  test('parses approval events that use action_id', () {
    final action = DeviceAction.fromJson({
      'action_id': 'action-1',
      'tool': 'device_alarm_create',
      'title': '创建闹钟',
      'description': '07:00',
      'arguments': <String, dynamic>{'label': '起床'},
    });

    expect(action.id, 'action-1');
  });

  test('stores each streamed sentence as a separate assistant bubble',
      () async {
    final controller = ChatController(gateway: FakeChatGateway());

    await controller.send('测试');

    expect(controller.status, ChatStatus.idle);
    expect(controller.messages, hasLength(3));
    expect(controller.messages.first.role, ChatRole.user);
    expect(controller.messages[1].content, '第一句。');
    expect(controller.messages[2].content, '第二句！');
    expect(controller.messages.first.id, 'user-message-1');
    expect(controller.messages.first.createdAt, FakeChatGateway.userCreatedAt);
    expect(
      controller.messages.skip(1).map((message) => message.createdAt),
      everyElement(FakeChatGateway.assistantCreatedAt),
    );
    expect(
      controller.messages.skip(1).map((message) => message.assistantRole),
      everyElement('teacher'),
    );
    expect(controller.messages.last.id, 'message-1');
  });

  testWidgets('stream completion keeps later bubbles queued until their turn',
      (tester) async {
    final controller = ChatController(gateway: FakeChatGateway());
    final sending = controller.send('测试');
    await tester.pump();
    expect(
        controller.messages.map((message) => message.content), ['测试', '第一句。']);
    expect(controller.timelineItems, hasLength(2));
    expect(controller.isBusy, isTrue);
    await tester.pump(const Duration(milliseconds: 999));
    expect(controller.messages, hasLength(2));
    await tester.pump(const Duration(milliseconds: 2001));
    await sending;
    expect(controller.messages.last.content, '第二句！');
    expect(controller.messages.last.id, 'message-1');
    expect(controller.isBusy, isFalse);
    controller.dispose();
  });

  testWidgets('leaving chat cancels pacing without losing received bubbles',
      (tester) async {
    final controller = ChatController(gateway: FakeChatGateway());
    final sending = controller.send('测试');
    await tester.pump();
    expect(controller.messages, hasLength(2));
    controller.deactivateSpeech();
    await sending;
    expect(controller.messages, hasLength(3));
    expect(controller.timelineItems, hasLength(3));
    await tester.pump(const Duration(seconds: 3));
    expect(controller.messages, hasLength(3));
    controller.dispose();
  });

  testWidgets('read aloud waits for playback and reveals matching text first',
      (tester) async {
    const channel = MethodChannel('bingo/device_tools');
    final firstPlayback = Completer<void>();
    final playback = <int>[];
    var finishes = 0;
    late ChatController controller;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'playReplyAudio') {
        final bytes = call.arguments as Uint8List;
        playback.add(bytes.first);
        expectSync(controller.messages.last.content,
            bytes.first == 1 ? '早呀' : '昨晚睡得怎么样？');
      }
      if (call.method == 'finishReplyAudio' && finishes++ == 0) {
        await firstPlayback.future;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final gateway = SegmentedSpeechGateway();
    controller = ChatController(gateway: gateway);
    await controller.activateSpeech();
    await controller.setReadAloud(true);
    final sending = controller.send('你好');
    await tester.pump();
    expect(gateway.readAloud, isTrue);
    expect(playback, [1]);
    expect(controller.messages.map((message) => message.content), ['你好', '早呀']);
    await tester.pump(const Duration(seconds: 4));
    expect(controller.speechError, isNull);
    expect(playback, [1]);
    expect(controller.messages, hasLength(2));
    firstPlayback.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await sending;
    expect(playback, [1, 2]);
    expect(controller.messages.last.content, '昨晚睡得怎么样？');
    controller.dispose();
    await tester.pump();
  });

  test('sends images through the normal chat stream', () async {
    final gateway = FakeChatGateway();
    final controller = ChatController(gateway: gateway);
    final bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);

    await controller.sendImage(bytes, mimeType: 'image/jpeg');

    expect(gateway.lastContent, isEmpty);
    expect(gateway.lastImages, hasLength(1));
    expect(gateway.lastImages.single.bytes, bytes);
    expect(controller.messages.first.content, '[图片]');
    expect(controller.messages.first.imageId, 'image-1');
    expect(controller.messages.skip(1).map((item) => item.content), [
      '第一句。',
      '第二句！',
    ]);
  });

  test('surfaces an incoming call exactly once', () async {
    final controller = ChatController(gateway: IncomingCallChatGateway());

    await controller.send('你怎么不给我打电话？');

    expect(controller.takeIncomingCall(), IncomingCallChatGateway.invitation);
    expect(controller.takeIncomingCall(), isNull);
    expect(controller.messages.last.content, '我给你打过来啦。');
  });

  test('new input interrupts the visible run and ignores its late events',
      () async {
    final gateway = InterruptibleChatGateway();
    final controller = ChatController(gateway: gateway);

    final first = controller.send('第一个问题');
    await Future<void>.delayed(Duration.zero);
    final firstRun = gateway.calls.single.runId;
    gateway.streams[firstRun]!
      ..add(const ChatStarted('conversation-1'))
      ..add(const ChatSegment('回答了一半。'));
    await Future<void>.delayed(Duration.zero);

    final second = controller.send('补充问题');
    await Future<void>.delayed(Duration.zero);
    final secondCall = gateway.calls.last;
    expect(secondCall.supersedesRunId, firstRun);
    expect(controller.messages[1].status, ChatMessageStatus.interrupted);
    expect(controller.messages[2].content, '补充问题');

    final firstStream = gateway.streams[firstRun]!;
    firstStream
      ..add(const ChatSegment('这句不应显示。'))
      ..add(const ChatFinished('stale-message'));
    await firstStream.close();
    final secondStream = gateway.streams[secondCall.runId]!;
    secondStream
      ..add(const ChatStarted('conversation-1'))
      ..add(const ChatSegment('合并上下文后的回答。'))
      ..add(const ChatFinished('final-message'));
    await secondStream.close();
    await Future.wait([first, second]);

    expect(
      controller.messages.map((message) => message.content),
      ['第一个问题', '回答了一半。', '补充问题', '合并上下文后的回答。'],
    );
    expect(controller.messages.last.status, ChatMessageStatus.completed);
    expect(controller.status, ChatStatus.idle);
  });

  test('executes a device action only after explicit approval', () async {
    final gateway = FakeApprovalGateway();
    final executor = FakeDeviceToolExecutor();
    final store = MemoryChatStore();
    final controller = ChatController(
      gateway: gateway,
      deviceActions: gateway,
      deviceToolExecutor: executor,
      localStore: store,
    );
    await controller.bindUser('user-1');

    await controller.send('明早七点叫我');
    expect(controller.deviceActions.single.status, 'pending');
    expect(executor.executed, isFalse);

    await controller.approveDeviceAction(controller.deviceActions.single);

    expect(gateway.approved, isTrue);
    expect(executor.executed, isTrue);
    expect(gateway.completed, isTrue);
    expect(controller.deviceActions.single.status, 'succeeded');

    final actionIndex = controller.timelineItems.indexWhere(
      (item) => item is DeviceAction,
    );
    await controller.send('继续聊天');
    final newMessageIndex = controller.timelineItems.indexWhere(
      (item) => item is ChatMessage && item.content == '继续聊天',
    );
    expect(actionIndex, lessThan(newMessageIndex));

    final restored = ChatController(
      gateway: gateway,
      localStore: store,
    );
    await restored.bindUser('user-1');
    final restoredActionIndex = restored.timelineItems.indexWhere(
      (item) => item is DeviceAction && item.status == 'succeeded',
    );
    final restoredNewMessageIndex = restored.timelineItems.indexWhere(
      (item) => item is ChatMessage && item.content == '继续聊天',
    );
    expect(restoredActionIndex, lessThan(restoredNewMessageIndex));
  });

  test('saves streamed messages locally and restores the active chat',
      () async {
    final store = MemoryChatStore();
    final first = ChatController(
      gateway: FakeChatGateway(),
      localStore: store,
    );
    await first.bindUser('user-1');
    await first.send('本地记录测试');

    expect(store.activeId, 'conversation-1');
    expect(store.conversations['conversation-1']!.messages, hasLength(3));

    final restored = ChatController(
      gateway: FakeChatGateway(),
      localStore: store,
    );
    await restored.bindUser('user-1');

    expect(restored.messages, hasLength(3));
    expect(restored.messages.first.content, '本地记录测试');
    expect(restored.messages.last.content, '第二句！');
  });

  test('keeps a disconnected reply pending and restores it from the server',
      () async {
    const runId = 'mobile-recovery-run';
    final store = MemoryChatStore();
    store.conversations['conversation-1'] = const LocalConversation(
      id: 'conversation-1',
      title: 'Recovery',
      messages: [
        ChatMessage(
          id: 'local-user',
          role: ChatRole.user,
          content: 'Question',
          runId: runId,
        ),
        ChatMessage(
          id: 'local-partial',
          role: ChatRole.assistant,
          content: 'Partial.',
          runId: runId,
          status: ChatMessageStatus.streaming,
        ),
      ],
    );
    store.activeId = 'conversation-1';
    final gateway = RecoveringChatGateway(const [
      ChatMessage(
        id: 'server-user',
        role: ChatRole.user,
        content: 'Question',
        runId: runId,
      ),
    ]);
    final controller = ChatController(
      gateway: gateway,
      remoteHistory: gateway,
      localStore: store,
    );

    await controller.bindUser('user-1');
    expect(controller.status, ChatStatus.sending);
    expect(controller.messages.last.content, 'Partial.');

    gateway.remoteMessages = const [
      ChatMessage(
        id: 'server-user',
        role: ChatRole.user,
        content: 'Question',
        runId: runId,
      ),
      ChatMessage(
        id: 'server-assistant',
        role: ChatRole.assistant,
        content: 'Complete reply.',
        runId: runId,
      ),
    ];
    await controller.syncActiveConversation();

    expect(controller.status, ChatStatus.idle);
    expect(controller.messages.last.content, 'Complete reply.');
    expect(
      store.conversations['conversation-1']!.messages.last.content,
      'Complete reply.',
    );
    controller.dispose();
  });

  test('splits persisted assistant replies when restoring history', () async {
    final store = MemoryChatStore();
    store.conversations['conversation-1'] = LocalConversation(
      id: 'conversation-1',
      title: '历史消息',
      messages: const [
        ChatMessage(
          id: 'assistant-1',
          role: ChatRole.assistant,
          content: '第一句。第二句！最后一句',
        ),
      ],
    );
    store.activeId = 'conversation-1';
    final controller = ChatController(
      gateway: FakeChatGateway(),
      localStore: store,
    );

    await controller.bindUser('user-1');

    expect(
      controller.messages.map((message) => message.content),
      ['第一句。', '第二句！', '最后一句'],
    );
  });

  test('persists proactive messages before acknowledging them', () async {
    final store = MemoryChatStore();
    store.conversations['conversation-1'] = const LocalConversation(
      id: 'conversation-1',
      title: '旧对话',
      messages: [],
    );
    store.activeId = 'conversation-1';
    final engagement = FakeEngagementGateway(
      proactive: [
        ProactiveMessage(
          id: 'proactive-1',
          conversationId: 'conversation-1',
          messageId: 'message-proactive-1',
          content: '刚才那件事后来怎么样了？',
          stage: 1,
          createdAt: DateTime(2026),
        ),
      ],
    );
    final controller = ChatController(
      gateway: FakeChatGateway(),
      localStore: store,
      engagement: engagement,
    );

    await controller.bindUser('user-1');

    expect(controller.messages.single.content, '刚才那件事后来怎么样了？');
    expect(
      store.conversations['conversation-1']!.messages.single.id,
      'message-proactive-1',
    );
    expect(engagement.acknowledged, ['proactive-1']);
  });

  test('selecting a recommendation clears all rows and sends it', () async {
    final store = MemoryChatStore();
    final engagement = FakeEngagementGateway(
      recommendations: ['问题一', '问题二', '问题三'],
    );
    final controller = ChatController(
      gateway: FakeChatGateway(),
      localStore: store,
      engagement: engagement,
    );
    await controller.bindUser('user-1');
    expect(controller.recommendations, hasLength(3));

    await controller.sendRecommendation('问题二');

    expect(controller.recommendations, isEmpty);
    expect(engagement.cleared, isTrue);
    expect(controller.messages.first.content, '问题二');
  });

  testWidgets('shows recommendation label without leading arrows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemoryChatStore();
    store.conversations['conversation-1'] = LocalConversation(
      id: 'conversation-1',
      title: '已有对话',
      messages: [
        for (var i = 0; i < 30; i++)
          ChatMessage(
              id: 'message-$i', role: ChatRole.assistant, content: '聊天记录 $i'),
      ],
    );
    store.activeId = 'conversation-1';
    final controller = ChatController(
      gateway: FakeChatGateway(),
      localStore: store,
      engagement: FakeEngagementGateway(
        recommendations: ['聊聊', '有趣话题二', '今天有什么适合周末出门放松的活动？'],
      ),
    );
    await controller.bindUser('user-1');

    await tester.pumpWidget(MaterialApp(
      home: ChatPage(
        controller: controller,
        assistantName: 'Bingo',
        assistantRole: '生活助理',
        speechGateway: FakeSpeechGateway(),
        onStartCall: () {},
        onIncomingCall: (_) async {},
        onOpenSettings: () {},
      ),
    ));

    expect(find.text('为您推荐'), findsOneWidget);
    expect(find.text('个人助理'), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);
    expect(find.text('聊聊'), findsOneWidget);
    final shortBubble = find
        .ancestor(of: find.text('聊聊'), matching: find.byType(InkWell))
        .first;
    final mediumBubble = find
        .ancestor(of: find.text('有趣话题二'), matching: find.byType(InkWell))
        .first;
    final longBubble = find
        .ancestor(
            of: find.text('今天有什么适合周末出门放松的活动？'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(shortBubble).width,
        lessThan(tester.getSize(mediumBubble).width));
    expect(tester.getSize(mediumBubble).width,
        lessThan(tester.getSize(longBubble).width));
    expect(tester.getTopLeft(shortBubble).dy, tester.getTopLeft(longBubble).dy);
    expect(tester.getTopLeft(shortBubble).dx,
        lessThan(tester.getTopLeft(longBubble).dx));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.north_west_rounded), findsNothing);
    expect(
      find.ancestor(
        of: find.text('为您推荐'),
        matching: find.byType(ListView),
      ),
      findsNothing,
    );
    final dock = find.byKey(const ValueKey('chat-recommendations-dock'));
    final beforeScroll = tester.getTopLeft(dock);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(dock), beforeScroll);
    expect(tester.getBottomLeft(dock).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(MessageInput)).dy));
  });

  testWidgets(
      'empty chat uses selected avatar and new suggestions without settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = FakeChatGateway();
    final controller = ChatController(gateway: gateway);
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            controller: controller,
            assistantName: '暖暖',
            assistantRole: '男朋友',
            speechGateway: FakeSpeechGateway(),
            onStartCall: () {},
            onIncomingCall: (_) async {},
            onOpenSettings: () {})));
    await tester.pumpAndSettle();
    expect(find.text('今天想聊点什么？'), findsOneWidget);
    expect(find.text('今天不太开心，安慰我一下吧'), findsOneWidget);
    expect(find.text('有件事让我纠结，陪我一起想想'), findsOneWidget);
    expect(find.text('睡前陪我聊一会儿吧'), findsOneWidget);
    expect(find.text('我会记住重要的事，也会一直接着聊'), findsNothing);
    expect(find.text('看一下今天有什么新闻'), findsNothing);
    expect(find.text('帮我整理今天的计划'), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);
    final avatars =
        tester.widgetList<AssistantAvatar>(find.byType(AssistantAvatar));
    expect(avatars.length, 2);
    expect(avatars.every((avatar) => avatar.role == '男朋友'), isTrue);
    final welcomeAvatar = find.byKey(const ValueKey('empty-chat-avatar'));
    expect(tester.getSize(welcomeAvatar), const Size(104, 104));
    expect(
        find.descendant(
            of: welcomeAvatar, matching: find.byType(ClipRSuperellipse)),
        findsOneWidget);
    expect(
        find.descendant(of: welcomeAvatar, matching: find.byType(DecoratedBox)),
        findsNothing);
    expect(find.text('为您推荐'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    final first = tester.getCenter(find.text('今天不太开心，安慰我一下吧'));
    final second = tester.getCenter(find.text('有件事让我纠结，陪我一起想想'));
    final third = tester.getCenter(find.text('睡前陪我聊一会儿吧'));
    expect(first.dy, second.dy);
    expect(second.dy, third.dy);
    expect(first.dx, lessThan(second.dx));
    expect(second.dx, lessThan(third.dx));
    final firstLabel = tester.widget<Text>(find.text('今天不太开心，安慰我一下吧'));
    expect(firstLabel.maxLines, 1);
    await tester.tap(find.text('今天不太开心，安慰我一下吧'));
    await tester.pumpAndSettle();
    expect(gateway.lastContent, '今天不太开心，安慰我一下吧');
    expect(find.text('第一句。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
