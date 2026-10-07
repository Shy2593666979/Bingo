import 'dart:convert';
import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_page.dart';
import 'package:bingo/features/chat/presentation/companion_moment_page.dart';
import 'package:bingo/features/chat/presentation/companion_records_page.dart';
import 'package:bingo/features/chat/presentation/widgets/chat_menu_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway
    implements ChatGateway, ReplySpeechGateway, MomentGateway, SpeechGateway {
  @override
  bool readAloud = false;
  final sent = <String>[];
  final finished = <String>[];
  final narratives = <String>[];
  Completer<void>? completionGate;
  VoidCallback? onFinish;
  @override
  Future<String> transcribe(Uint8List audio) async => '';

  @override
  Future<void> cancelMoment(String runId) async {}

  @override
  Stream<ChatStreamEvent> generateMoment(
      {required String conversationId,
      required String runId,
      required String mode,
      required String previous,
      required int seconds,
      required double charactersPerSecond,
      required bool closing}) async* {
    narratives.add(previous);
    yield const ChatSegment('月光洒在安静的小屋里，小兔子轻轻关上了窗。');
    yield ChatAudio(Uint8List(480000));
    yield const ChatAudioDone();
  }

  @override
  Stream<ChatStreamEvent> finishMoment(
      {required String conversationId,
      required String sessionId,
      required String feature,
      required String summary}) async* {
    finished.add('[$feature] $summary');
    onFinish?.call();
    if (completionGate != null) await completionGate!.future;
    yield ChatStarted(conversationId);
    yield const ChatSegment('我听见啦，慢慢来，我陪着你。');
    yield ChatFinished(sessionId);
  }

  @override
  Future<void> stopReplySpeech() async {}
  @override
  Stream<ChatStreamEvent> send(
      {String? conversationId,
      required String content,
      required String runId,
      String? supersedesRunId,
      List<ChatImageUpload> images = const []}) async* {
    sent.add(content);
    yield ChatStarted(conversationId ?? 'conversation');
    yield const ChatSegment('我听见啦，慢慢来，我陪着你。');
    yield const ChatFinished('reply');
    if (readAloud) {
      yield ChatAudio(Uint8List(4800));
      yield const ChatAudioDone();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final saved = <String, String>{};
  final nativeCalls = <MethodCall>[];
  late ChatController controller;
  late _Gateway gateway;
  const storeChannel = MethodChannel('bingo/local_chat');
  const deviceChannel = MethodChannel('bingo/device_tools');

  setUp(() async {
    saved.clear();
    nativeCalls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(storeChannel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final key = '${arguments['user_id']}:${arguments['key']}';
      if (call.method == 'readCompanionData') return saved[key];
      if (call.method == 'writeCompanionData') {
        saved[key] = arguments['data'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(deviceChannel, (call) async {
      nativeCalls.add(call);
      return null;
    });
    gateway = _Gateway();
    controller = ChatController(gateway: gateway);
    await controller.bindConversation('user', 'conversation', '女朋友');
    await controller.activateSpeech();
  });
  tearDown(() {
    controller.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(storeChannel, null);
    messenger.setMockMethodCallHandler(deviceChannel, null);
  });

  Future<void> open(WidgetTester tester, CompanionMoment kind) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            controller: controller,
            assistantName: '甜甜',
            assistantRole: '女朋友',
            speechGateway: gateway,
            onStartCall: () {},
            onIncomingCall: (_) async {},
            onOpenSettings: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多功能'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kind.title).last);
    await tester.pumpAndSettle();
  }

  for (final kind in CompanionMoment.values) {
    testWidgets('${kind.title} opens with mint layout without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await open(tester, kind);
      expect(find.text(kind.title), findsOneWidget);
      expect(
          tester
              .widgetList<ChatMenuIcon>(find.byType(ChatMenuIcon))
              .every((icon) => icon.symbol == kind.icon),
          isTrue);
      expect(find.byType(ChatMenuIcon), findsWidgets);
      for (final button
          in tester.widgetList<FilledButton>(find.byType(FilledButton))) {
        expect(button.style?.backgroundColor?.resolve({}),
            BingoPalette.chatMenuSurface);
        expect(button.style?.foregroundColor?.resolve({}),
            BingoPalette.chatMenuInk);
      }
      expect(find.text('和甜甜'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('focus starts and pauses into local scoped storage',
      (tester) async {
    await open(tester, CompanionMoment.focus);
    await tester.tap(find.text('和甜甜开始专注'));
    await tester.pumpAndSettle();
    expect(find.text('25:00'), findsOneWidget);
    await tester.tap(find.text('暂停一下'));
    await tester.pumpAndSettle();
    final data = jsonDecode(saved['user:moments:conversation:focus']!) as Map;
    expect((data['focus'] as Map)['deadline'], isNull);
    expect(find.text('继续专注'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returns to chat before requesting the end reply',
      (tester) async {
    await open(tester, CompanionMoment.diary);
    gateway.completionGate = Completer<void>();
    gateway.onFinish =
        () => expect(find.byType(CompanionMomentPage), findsNothing);
    await tester.enterText(find.byType(TextField), '只有小记页能看到的正文');
    await tester.ensureVisible(find.text('保存今日小记'));
    await tester.tap(find.text('保存今日小记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(CompanionMomentPage), findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(gateway.finished.length, 1);
    expect(controller.messages.length, 1);
    expect(controller.messages.single.content, isNot(contains('只有小记页能看到的正文')));
    gateway.completionGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.messages.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('automatic focus completion returns before the model responds',
      (tester) async {
    saved['user:moments:conversation:focus'] = jsonEncode({
      'entries': [],
      'activity': '学习',
      'focus': {
        'total': 1500,
        'remaining': 1500,
        'completed': false,
        'deadline': DateTime.now()
            .subtract(const Duration(seconds: 2))
            .toIso8601String()
      }
    });
    gateway.completionGate = Completer<void>();
    gateway.onFinish =
        () => expect(find.byType(CompanionMomentPage), findsNothing);
    await open(tester, CompanionMoment.focus);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(CompanionMomentPage), findsNothing);
    expect(gateway.finished.length, 1);
    expect(controller.messages.length, 1);
    gateway.completionGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.messages.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('diary body stays local and only an end summary reaches chat',
      (tester) async {
    await open(tester, CompanionMoment.diary);
    await tester.enterText(find.byType(TextField), '今天走了一段很舒服的路');
    await tester.tap(find.text('很开心'));
    await tester.ensureVisible(find.text('保存今日小记'));
    await tester.tap(find.text('保存今日小记'));
    await tester.pumpAndSettle();
    expect(gateway.sent, isEmpty);
    var data = jsonDecode(saved['user:moments:conversation:diary']!) as Map;
    expect((data['entries'] as List).length, 1);
    expect(((data['entries'] as List).single as Map)['mood'], '很开心');
    expect(gateway.finished.single, contains('今天的心情是很开心'));
    expect(gateway.finished.single, isNot(contains('小记正文只保存在本地')));
    expect(find.byType(CompanionMomentPage), findsNothing);
    await open(tester, CompanionMoment.diary);
    await tester.enterText(find.byType(TextField), '现在想和你分享');
    await tester.ensureVisible(find.text('保存今日小记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存今日小记'));
    await tester.pumpAndSettle();
    data = jsonDecode(saved['user:moments:conversation:diary']!) as Map;
    expect(gateway.sent, isEmpty);
    expect(gateway.finished.length, 2);
    expect(gateway.finished.join(), isNot(contains('现在想和你分享')));
    expect(gateway.finished.join(), isNot(contains('今天走了一段很舒服的路')));
    expect(((data['entries'] as List).first as Map)['reply'], '');
    expect(controller.messages.last.content, '我听见啦，慢慢来，我陪着你。');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('promise schedules and completing it cancels the reminder',
      (tester) async {
    await open(tester, CompanionMoment.promise);
    await tester.enterText(find.byType(TextField), '明天一起散步');
    await tester.tap(find.text('存下这个小约定'));
    await tester.pumpAndSettle();
    expect(gateway.finished.length, 1);
    expect(
        nativeCalls
            .where((call) => call.method == 'scheduleCompanionReminder')
            .length,
        1);
    expect(find.byType(CompanionMomentPage), findsNothing);
    await open(tester, CompanionMoment.promise);
    expect(find.text('明天一起散步'), findsNothing);
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.byType(CompanionRecordsPage), findsOneWidget);
    await tester.tap(find.text('明天一起散步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成了'));
    await tester.pumpAndSettle();
    final data = jsonDecode(saved['user:moments:conversation:promise']!) as Map;
    expect(((data['entries'] as List).single as Map)['status'], 'completed');
    expect(nativeCalls.any((call) => call.method == 'cancelCompanionReminder'),
        isTrue);
    expect(gateway.sent, isEmpty);
    expect(gateway.finished.length, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'sleep explicitly streams current partner audio without changing chat preference',
      (tester) async {
    await open(tester, CompanionMoment.sleep);
    await tester.tap(find.text('开始陪伴'));
    await tester.pumpAndSettle();
    expect(gateway.sent, isEmpty);
    expect(gateway.finished, isEmpty);
    expect(controller.messages, isEmpty);
    expect(gateway.narratives.length, 2);
    expect(gateway.narratives.last, contains('小兔子'));
    expect(controller.readAloudEnabled, isFalse);
    expect(nativeCalls.any((call) => call.method == 'playReplyAudio'), isTrue);
    await tester.ensureVisible(find.text('暂停陪伴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂停陪伴'));
    await tester.pumpAndSettle();
    expect(nativeCalls.last.method, 'stopReplyAudio');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
