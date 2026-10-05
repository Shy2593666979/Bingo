import 'dart:async';
import 'dart:typed_data';

import 'package:bingo/core/device/device_tool_executor.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/local_chat_store.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/features/chat/presentation/chat_page.dart';
import 'package:bingo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
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

  @override
  Future<List<ConversationSummary>> listConversations() async => const [];

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async =>
      List.of(remoteMessages);

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
  testWidgets('chat header centers name and connects back and call actions',
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
    expect(tester.getCenter(find.text('暖暖')).dx, closeTo(180, 1));
    expect(tester.getCenter(find.byTooltip('返回角色')).dx,
        lessThan(tester.getCenter(find.text('暖暖')).dx));
    expect(tester.getCenter(find.byTooltip('语音通话')).dx,
        greaterThan(tester.getCenter(find.text('暖暖')).dx));
    await tester.tap(find.byTooltip('语音通话'));
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
    final store = MemoryChatStore();
    store.conversations['conversation-1'] = const LocalConversation(
      id: 'conversation-1',
      title: '已有对话',
      messages: [
        ChatMessage(id: 'message-1', role: ChatRole.assistant, content: '聊天记录'),
      ],
    );
    store.activeId = 'conversation-1';
    final controller = ChatController(
      gateway: FakeChatGateway(),
      localStore: store,
      engagement: FakeEngagementGateway(
        recommendations: ['有趣话题一', '有趣话题二', '有趣话题三'],
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
    expect(find.text('有趣话题一'), findsOneWidget);
    expect(find.byIcon(Icons.north_west_rounded), findsNothing);
    expect(
      find.ancestor(
        of: find.text('为您推荐'),
        matching: find.byType(ListView),
      ),
      findsOneWidget,
    );
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
    expect(avatars.length, 1);
    expect(avatars.every((avatar) => avatar.role == '男朋友'), isTrue);
    final welcomeAvatar = find.byKey(const ValueKey('empty-chat-avatar'));
    expect(tester.getSize(welcomeAvatar), const Size(104, 104));
    expect(find.descendant(of: welcomeAvatar, matching: find.byType(ClipOval)),
        findsOneWidget);
    expect(
        find.descendant(of: welcomeAvatar, matching: find.byType(DecoratedBox)),
        findsNothing);
    final first =
        tester.getCenter(find.widgetWithText(ActionChip, '今天不太开心，安慰我一下吧'));
    final second =
        tester.getCenter(find.widgetWithText(ActionChip, '有件事让我纠结，陪我一起想想'));
    final third =
        tester.getCenter(find.widgetWithText(ActionChip, '睡前陪我聊一会儿吧'));
    expect(first.dy, second.dy);
    expect(first.dx, lessThan(third.dx));
    expect(second.dx, greaterThan(third.dx));
    expect(third.dy, greaterThan(first.dy));
    final firstLabel = tester.widget<Text>(find.text('今天不太开心，安慰我一下吧'));
    expect(firstLabel.softWrap, isTrue);
    expect(firstLabel.maxLines, 3);
    expect(tester.getSize(find.text('今天不太开心，安慰我一下吧')).height, greaterThan(25));
    await tester.tap(find.text('今天不太开心，安慰我一下吧'));
    await tester.pumpAndSettle();
    expect(gateway.lastContent, '今天不太开心，安慰我一下吧');
    expect(find.text('第一句。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
