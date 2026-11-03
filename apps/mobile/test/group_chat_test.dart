import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/group_chat/presentation/group_controller.dart';
import 'package:bingo/features/group_chat/presentation/group_chat_page.dart';
import 'package:bingo/features/group_chat/presentation/group_info_page.dart';
import 'package:bingo/features/group_chat/presentation/create_group_page.dart';
import 'package:bingo/features/group_chat/presentation/widgets/chat_quote_card.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _message(
        String id, int seq, String type, String name, String? role) =>
    {
      'id': id,
      'seq': seq,
      'run_id': 'run-one',
      'sender_type': type,
      'sender_role_id': role,
      'sender_name': name,
      'content': '$name 的消息正文',
      'status': 'completed',
      'created_at': '2026-10-29T10:00:00Z'
    };
ChatGroup _group(
        {bool readAloud = false,
        String firstName = '甜甜',
        String firstRole = '女朋友'}) =>
    ChatGroup.fromJson({
      'read_aloud': readAloud,
      'id': 'group-one',
      'human': {'id': 'human-one', 'name': '小鱼'},
      'name': '快乐小窝',
      'description': '一起聊聊今天的生活',
      'cover': 'coffee',
      'allow_ai_to_ai': true,
      'mentions_enabled': true,
      'proactive_enabled': false,
      'muted': false,
      'pinned': false,
      'last_activity_at': '2026-10-29T10:00:00Z',
      'members': [
        {
          'id': 'ai-one',
          'name': firstName,
          'role_name': firstRole,
          'avatar_asset': 'girlfriend.png',
          'active': true
        },
        {
          'id': 'ai-two',
          'name': '暖暖',
          'role_name': '男朋友',
          'avatar_asset': 'boyfriend.png',
          'active': true
        },
      ]
    });

class _Gateway
    implements GroupGateway, GroupV2Gateway, RoleGateway, SpeechGateway {
  Map<String, dynamic>? sentV2;
  Map<String, dynamic>? updated;
  bool sound = false;
  @override
  Future<ChatGroup> updateGroup(String id, Map<String, dynamic> data) async {
    updated = data;
    if (data['read_aloud'] is bool) sound = data['read_aloud'] as bool;
    return _group(readAloud: sound);
  }

  @override
  Future<String> sendGroupV2(
      String id, String text, List<String> mentions, String clientId,
      {bool mentionAll = false,
      List<Map<String, String>> mentionTargets = const [],
      String? replyToMessageId}) async {
    sentV2 = {
      'text': text,
      'mentions': mentions,
      'all': mentionAll,
      'quote': replyToMessageId
    };
    return sendGroup(id, text, mentions, clientId);
  }

  @override
  Future<List<GroupChatMessage>> groupMessageContext(
          String id, String messageId) async =>
      rows;
  final sentIds = <String>[];
  bool failSnapshotOnce = false, _accepted = false;
  bool failAckOnce = false;
  Map<String, dynamic>? created;
  final rows = [
    GroupChatMessage.fromJson(_message('one', 1, 'assistant', '甜甜', 'ai-one')),
    GroupChatMessage.fromJson(_message('two', 2, 'user', '我', null)),
    GroupChatMessage.fromJson(_message('three', 3, 'assistant', '暖暖', 'ai-two'))
  ];
  @override
  Future<List<RoleOption>> listRoles() async => [
        for (var i = 0; i < 9; i++)
          RoleOption(
              id: 'role-$i',
              name: '搭子$i',
              builtin: false,
              description: '自然温柔的陪伴搭子')
      ];
  @override
  Future<ChatGroup> getGroup(String id) async => _group();
  @override
  Future<List<ChatGroup>> listGroups() async => [_group()];
  @override
  Future<List<GroupChatMessage>> groupMessages(String id, {int? before}) async {
    if (_accepted && failSnapshotOnce) {
      failSnapshotOnce = false;
      throw StateError('connection');
    }
    return rows;
  }

  @override
  Future<String> sendGroup(
      String id, String text, List<String> mentions, String clientId) async {
    _accepted = true;
    if (!sentIds.contains(clientId)) {
      rows.add(GroupChatMessage.fromJson({
        ..._message('sent-$clientId', 4, 'user', '我', null),
        'content': text,
        'client_message_id': clientId,
      }));
    }
    sentIds.add(clientId);
    if (failAckOnce) {
      failAckOnce = false;
      throw StateError('response lost after accepting');
    }
    return 'run-one';
  }

  @override
  Future<Map<String, dynamic>> groupEvents(
          String id, String run, int after) async =>
      {'events': [], 'status': 'completed', 'last_event_seq': 0};
  @override
  Future<void> readGroup(String id, int seq) async {}
  @override
  Future<String> transcribe(Uint8List bytes) async => '语音消息';
  @override
  Future<ChatGroup> createGroup(Map<String, dynamic> data) async {
    created = data;
    return _group();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedGateway extends _Gateway {
  final ack = Completer<void>();
  @override
  Future<String> sendGroup(
      String id, String text, List<String> mentions, String clientId) async {
    await ack.future;
    return super.sendGroup(id, text, mentions, clientId);
  }
}

class _RenamedGateway extends _Gateway {
  @override
  Future<ChatGroup> getGroup(String id) async =>
      _group(firstName: '陈叔', firstRole: '邻家大叔');
}

class _AudioGateway extends _Gateway implements GroupSpeechGateway {
  final streams = <StreamController<Uint8List>>[];
  final played = <String>[];
  int stops = 0;
  @override
  Stream<Uint8List> groupMessageSpeech(String groupId, String messageId) {
    played.add(messageId);
    final stream = StreamController<Uint8List>();
    streams.add(stream);
    return stream.stream;
  }

  @override
  void stopGroupSpeech() {
    stops++;
  }
}

void main() {
  testWidgets(
      'human mentions appear in the body with the real name, without badge',
      (tester) async {
    for (final entry in {
      '你觉得呢？': '@小鱼 你觉得呢？',
      '@我，你觉得呢？': '@小鱼，你觉得呢？',
      '@小鱼 你觉得呢？': '@小鱼 你觉得呢？',
    }.entries) {
      final gateway = _Gateway();
      gateway.rows[0] = GroupChatMessage.fromJson({
        ..._message('one', 1, 'assistant', '甜甜', 'ai-one'),
        'content': entry.key,
        'mention_targets': [
          {'type': 'user', 'id': 'human-one'}
        ]
      });
      await tester.pumpWidget(MaterialApp(
          home: GroupChatPage(
              key: ValueKey(entry.key),
              groupId: 'group-one',
              gateway: gateway,
              roles: gateway,
              speech: gateway)));
      await tester.pumpAndSettle();
      final rich = tester.widget<RichText>(find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == entry.value));
      final mentions = <TextSpan>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == '@小鱼') mentions.add(span);
        return true;
      });
      expect(mentions, hasLength(1));
      expect(mentions.single.style!.color, BingoPalette.primaryText);
      expect(find.text('@我'), findsNothing);
      expect(gateway.rows[0].content, entry.key);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), (_) => null));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), null));
  testWidgets(
      'AI avatar taps use role ID and long presses insert selected mentions',
      (tester) async {
    final gateway = _RenamedGateway();
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: GroupChatPage(
            groupId: 'group-one',
            gateway: gateway,
            roles: gateway,
            speech: gateway,
            onOpenRoleDetails: opened.add)));
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('group-message-avatar-one'));
    final second = find.byKey(const ValueKey('group-message-avatar-three'));
    await tester.tap(first);
    await tester.tap(second);
    expect(opened, ['ai-one', 'ai-two']);
    await tester.enterText(find.byType(TextField), '先聊聊 ');
    await tester.longPress(first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '先聊聊 @陈叔 ');
    await tester.longPress(second);
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, '先聊聊 @陈叔 @暖暖 ');
    expect(input.focusNode!.hasFocus, isTrue);
    expect(find.text('复制'), findsNothing);
    expect(opened, ['ai-one', 'ai-two']);
    expect(gateway.sentIds, isEmpty);
    await tester.tap(find.byTooltip('发送消息'));
    await tester.pumpAndSettle();
    expect(gateway.sentV2!['mentions'], ['ai-one', 'ai-two']);
    expect(gateway.sentV2!['text'], '先聊聊 @陈叔 @暖暖');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'renamed companion updates sender and quote without rewriting history',
      (tester) async {
    final gateway = _RenamedGateway();
    gateway.rows[0] = GroupChatMessage.fromJson({
      ..._message('one', 1, 'assistant', '文清', 'ai-one'),
      'content': '文清是当时的称呼。',
    });
    gateway.rows[1] = GroupChatMessage.fromJson({
      ..._message('two', 2, 'user', '我', null),
      'reply_to_message_id': 'one',
      'reply_to': {'sender_name': '文清', 'content': '旧记录'},
    });
    await tester.pumpWidget(MaterialApp(
        home: GroupChatPage(
            groupId: 'group-one',
            gateway: gateway,
            roles: gateway,
            speech: gateway)));
    await tester.pumpAndSettle();
    expect(find.text('陈叔'), findsNWidgets(2));
    expect(find.text('文清'), findsNothing);
    expect(
        tester.widget<ChatQuoteCard>(find.byType(ChatQuoteCard)).sender, '陈叔');
    expect(gateway.rows.first.name, '文清');
    expect(gateway.rows.first.content, '文清是当时的称呼。');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('both AI broadcast labels are highlighted as real mentions',
      (tester) async {
    for (final label in ['全部搭子', '全体搭子']) {
      final gateway = _Gateway();
      final content = '@$label 每个人说一句吧。';
      gateway.rows[0] = GroupChatMessage.fromJson({
        ..._message('one', 1, 'assistant', '甜甜', 'ai-one'),
        'content': content,
        'mention_all': true,
        'mentions': ['ai-two'],
        'mention_targets': [
          {'type': 'role', 'id': 'ai-two'}
        ]
      });
      await tester.pumpWidget(MaterialApp(
          home: GroupChatPage(
              key: ValueKey(label),
              groupId: 'group-one',
              gateway: gateway,
              roles: gateway,
              speech: gateway)));
      await tester.pumpAndSettle();
      final rich = tester.widget<RichText>(find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == content));
      final tokens = <TextSpan>[];
      rich.text.visitChildren((s) {
        if (s is TextSpan && s.text == '@$label') tokens.add(s);
        return true;
      });
      final mention = tokens.single;
      expect(mention.style!.fontWeight, FontWeight.w600);
      expect(mention.style!.color, BingoPalette.primaryText);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets('sound is switched for the current group in group info',
      (tester) async {
    final gateway = _Gateway();
    await tester.pumpWidget(MaterialApp(
        home:
            GroupInfoPage(group: _group(), gateway: gateway, roles: gateway)));
    await tester.pumpAndSettle();
    final row =
        find.ancestor(of: find.text('开启声音'), matching: find.byType(ListTile));
    final toggle =
        find.descendant(of: row, matching: find.byType(CupertinoSwitch));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(gateway.updated, {'read_aloud': true});
    expect(tester.widget<CupertinoSwitch>(toggle).value, true);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(gateway.updated, {'read_aloud': false});
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'group messages have no waiting indicators or per-message audio controls',
      (tester) async {
    final gateway = _AudioGateway();
    await tester.pumpWidget(MaterialApp(
        home: GroupChatPage(
            groupId: 'group-one',
            gateway: gateway,
            roles: gateway,
            speech: gateway)));
    await tester.pumpAndSettle();
    expect(find.text('播放语音'), findsNothing);
    expect(find.textContaining('正在输入'), findsNothing);
    expect(gateway.played, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  Future<void> screen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
      'new-message pill floats without reserving or blocking the left side',
      (tester) async {
    await screen(tester);
    final previewKey = GlobalKey();
    final writePreview =
        Platform.environment['WRITE_NEW_MESSAGE_PREVIEW'] == '1';
    if (writePreview) {
      await tester.runAsync(() async {
        final font = FontLoader('BingoSans');
        for (final weight in ['Regular', 'Medium', 'Bold', 'Black']) {
          font.addFont(
              rootBundle.load('assets/fonts/HarmonyOS_Sans_SC_$weight.ttf'));
        }
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    final gateway = _Gateway();
    gateway.rows
      ..clear()
      ..addAll(List.generate(
          40,
          (index) => GroupChatMessage.fromJson(_message(
              'history-$index',
              index + 1,
              'assistant',
              index.isEven ? '甜甜' : '暖暖',
              index.isEven ? 'ai-one' : 'ai-two'))));
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: RepaintBoundary(
            key: previewKey,
            child: GroupChatPage(
                groupId: 'group-one',
                gateway: gateway,
                roles: gateway,
                speech: gateway))));
    await tester.pumpAndSettle();
    final viewport = find.byKey(const ValueKey('group-message-viewport'));
    final pill = find.byKey(const ValueKey('group-new-messages'));
    final scroll = tester
        .widget<SingleChildScrollView>(find.descendant(
            of: viewport, matching: find.byType(SingleChildScrollView)))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent - 600);
    await tester.pumpAndSettle();
    final before = tester.getRect(viewport);
    gateway.rows.add(GroupChatMessage.fromJson(
        _message('new', 41, 'assistant', '甜甜', 'ai-one')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('1条新消息'), findsOneWidget);
    expect(tester.getRect(viewport), before);
    final bounds = tester.getRect(pill);
    expect(bounds.width, lessThan(before.width / 2));
    expect(bounds.right, closeTo(before.right - 12, .1));
    expect(bounds.bottom, closeTo(before.bottom - 8, .1));
    if (writePreview) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final boundary = previewKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
            '../../docs/previews/assets/group-new-message-overlay/preview.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    final oldOffset = scroll.offset;
    await tester.dragFrom(
        Offset(before.left + 8, bounds.center.dy), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(oldOffset));
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(pill, findsNothing);
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, .1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('uncertain send retries the same client ID without duplicating messages',
      () async {
    final gateway = _Gateway()..failAckOnce = true;
    final controller = GroupController(gateway, 'group-one');
    await controller.load();
    expect(await controller.send('你好', ['ai-one']), false);
    expect(controller.canRetry, true);
    expect(await controller.send('你好', ['ai-one']), true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gateway.sentIds.length, 2);
    expect(gateway.sentIds.toSet().length, 1);
    expect(controller.messages.map((m) => m.id).toSet().length, 4);
    expect(controller.messages.where((m) => m.local), isEmpty);
    controller.dispose();
  });

  test('user message appears before any server acknowledgement', () async {
    final gateway = _DelayedGateway();
    final controller = GroupController(gateway, 'group-one');
    await controller.load();
    final sending = controller.send('我现在就要看到这条消息', []);
    expect(controller.messages.last.content, '我现在就要看到这条消息');
    expect(controller.messages.last.status, 'sending');
    expect(controller.messages.last.local, true);
    gateway.ack.complete();
    expect(await sending, true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(controller.messages.where((m) => m.content == '我现在就要看到这条消息'),
        hasLength(1));
    expect(controller.messages.where((m) => m.local), isEmpty);
    controller.dispose();
  });

  testWidgets(
      'single chat keeps only AI avatar without sender name or time header',
      (tester) async {
    await screen(tester);
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: const Scaffold(
            body: Column(children: [
          MessageBubble(
              message: ChatMessage(
                  id: 'ai', role: ChatRole.assistant, content: 'AI 正文'),
              assistantRole: '女朋友'),
          MessageBubble(
              message:
                  ChatMessage(id: 'me', role: ChatRole.user, content: '用户正文'),
              assistantRole: '女朋友'),
        ]))));
    await tester.pumpAndSettle();
    expect(find.byType(UserAvatar), findsNothing);
    expect(find.byType(AssistantAvatar), findsOneWidget);
    expect(find.text('甜甜'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'group chat shows avatars for both sides and role names plus time',
      (tester) async {
    await screen(tester);
    final gateway = _Gateway();
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: GroupChatPage(
            groupId: 'group-one',
            gateway: gateway,
            roles: gateway,
            speech: gateway)));
    await tester.pumpAndSettle();
    expect(find.text('快乐小窝'), findsOneWidget);
    expect(find.text(' (2)'), findsOneWidget);
    expect(find.text('甜甜'), findsOneWidget);
    expect(find.text('暖暖'), findsOneWidget);
    expect(find.text('18:00'), findsNWidgets(3));
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.byTooltip('@ 搭子'), findsNothing);
    expect(find.text('选择要 @ 的搭子'), findsNothing);
    await tester.enterText(find.byType(TextField), '@');
    await tester.pumpAndSettle();
    expect(find.text('选择要 @ 的搭子'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('甜甜').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '@甜甜 ');
    expect(find.text('选择要 @ 的搭子'), findsNothing);
    expect(find.byType(InputChip), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('all mentions and quote are sent before input clears',
      (tester) async {
    await screen(tester);
    final gateway = _Gateway();
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: GroupChatPage(
            groupId: 'group-one',
            gateway: gateway,
            roles: gateway,
            speech: gateway)));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('甜甜 的消息正文', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('引用回复'));
    await tester.pumpAndSettle();
    expect(find.text('回复 甜甜'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '@');
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部搭子'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    final c = field.controller!;
    c.value = TextEditingValue(
        text: '${c.text}周末去哪里？',
        selection: TextSelection.collapsed(offset: c.text.length + 6));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('发送消息'));
    await tester.pumpAndSettle();
    expect(gateway.sentV2?['all'], true);
    expect(gateway.sentV2?['quote'], 'one');
    expect(gateway.sentV2?['text'], contains('@全部搭子'));
    expect(c.text, isEmpty);
    expect(find.text('回复 甜甜'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'creation enforces eight members and submits a real group configuration',
      (tester) async {
    await screen(tester);
    final gateway = _Gateway();
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => CreateGroupPage(
                                gateway: gateway, roles: gateway))),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('允许 AI 自由接话'), findsNothing);
    expect(find.text('更多群聊设置'), findsNothing);
    expect(find.text('支持 @ 指定回复'), findsNothing);
    expect(find.text('主动开启话题'), findsNothing);
    for (var i = 4; i < 9; i++) {
      await tester.ensureVisible(find.text('搭子$i'));
      await tester.tap(find.text('搭子$i'));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(find.text('选择搭子 8/8'), -300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('选择搭子 8/8'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('创建群聊').last);
    await tester.pumpAndSettle();
    expect((gateway.created!['role_ids'] as List).length, 8);
    expect(gateway.created!['allow_ai_to_ai'], true);
    expect(gateway.created!['mentions_enabled'], true);
    expect(gateway.created!['proactive_enabled'], true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
