import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';

import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
import 'package:bingo/features/chat/presentation/widgets/chat_menu_icon.dart';
import 'package:bingo/features/stickers/sticker_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSpeechGateway implements SpeechGateway {
  bool called = false;

  @override
  Future<String> transcribe(Uint8List wavAudio) async {
    called = true;
    return '测试语音文字';
  }
}

class _DelayedRealtimeSpeechGateway
    implements SpeechGateway, RealtimeSpeechGateway {
  final session = Completer<RealtimeTranscriptionSession>();

  @override
  Future<RealtimeTranscriptionSession> startRealtimeTranscription() =>
      session.future;

  @override
  Future<String> transcribe(Uint8List wavAudio) async => '';
}

class _FakeRealtimeSession implements RealtimeTranscriptionSession {
  @override
  void addAudio(Uint8List pcmAudio) {}

  @override
  Future<void> cancel() async {}

  @override
  Future<String> finish() async => '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const deviceChannel = MethodChannel('bingo/device_tools');
  const audioControlChannel = MethodChannel('bingo/audio_stream');

  testWidgets('group plus offers only photo camera phone and location',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var called = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: MessageInput(
                    enabled: true,
                    referenceStyle: true,
                    initialVoiceMode: false,
                    groupMenu: true,
                    speechGateway: _FakeSpeechGateway(),
                    onSend: (_) {},
                    onCall: () => called = true)))));
    await tester.tap(find.byTooltip('更多功能'));
    await tester.pumpAndSettle();
    for (final label in ['照片', '相机', '电话', '位置']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(ChatMenuIcon), findsNWidgets(4));
    expect(find.text('群聊功能'), findsNothing);
    expect(find.text('群聊设置'), findsNothing);
    await tester.tap(find.text('电话'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'composer has voice on left and mutually exclusive more or send on right',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? sent;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: MessageInput(
                    enabled: true,
                    referenceStyle: true,
                    initialVoiceMode: false,
                    speechGateway: _FakeSpeechGateway(),
                    onCall: () {},
                    onSend: (value) => sent = value)))));
    await tester.pumpAndSettle();
    final plus = find.byTooltip('更多功能'), send = find.byTooltip('发送消息');
    expect(send, findsNothing);
    expect(tester.getSize(plus), const Size(43, 43));
    expect(
        tester.getSize(find.byKey(const ValueKey('more'))), const Size(27, 27));
    expect(tester.getCenter(find.byTooltip('语音输入')).dx,
        lessThan(tester.getCenter(find.byType(TextField)).dx));
    final actionPosition = tester.getCenter(plus);
    expect(actionPosition.dx,
        greaterThan(tester.getCenter(find.byType(TextField)).dx));
    await tester.enterText(find.byType(TextField), '今天也要开心');
    await tester.pumpAndSettle();
    expect(plus, findsNothing);
    expect(
        tester.getSize(find.byKey(const ValueKey('send'))), const Size(32, 32));
    expect(tester.getSize(send), const Size(43, 43));
    expect(tester.getCenter(send), actionPosition);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(sent, '今天也要开心');
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(find.text('语音输入'), findsNothing);
    expect(find.text('键盘输入'), findsNothing);
    await tester.tap(find.byTooltip('语音输入'));
    await tester.pumpAndSettle();
    expect(find.text('按住说话'), findsOneWidget);
    await tester.tap(find.byTooltip('键盘输入'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  setUp(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(deviceChannel, (_) async => null);
    messenger.setMockMethodCallHandler(audioControlChannel, (_) async => null);
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(deviceChannel, null);
    messenger.setMockMethodCallHandler(audioControlChannel, null);
  });

  testWidgets('shows WeChat-style recording actions while sliding',
      (tester) async {
    String? sent;
    final speech = _FakeSpeechGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(
              enabled: true,
              speechGateway: speech,
              onSend: (value) => sent = value,
              onCall: () {},
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('按住说话')),
    );
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsOneWidget);
    expect(find.text('转文字'), findsOneWidget);
    expect(find.text('松开 发送'), findsOneWidget);

    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    expect(find.text('松开转文字'), findsOneWidget);

    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(find.text('转文字'), findsNothing);
    expect(speech.called, isFalse);
    expect(sent, isNull);
  });

  testWidgets('shows recording overlay before realtime ASR is connected',
      (tester) async {
    final speech = _DelayedRealtimeSpeechGateway();
    var audioCaptureStarted = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(deviceChannel, (call) async {
      if (call.method == 'startAudioCapture') audioCaptureStarted = true;
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageInput(
            enabled: true,
            speechGateway: speech,
            onSend: (_) {},
            onCall: () {},
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('按住说话')),
    );
    await tester.pump();

    expect(find.text('松开 发送'), findsOneWidget);
    expect(audioCaptureStarted, isTrue);

    await gesture.cancel();
    speech.session.complete(_FakeRealtimeSession());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('opens the more panel and starts a call', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageInput(
            enabled: true,
            speechGateway: _FakeSpeechGateway(),
            onSend: (_) {},
            onCall: () => called = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多功能'));
    await tester.pumpAndSettle();

    expect(find.text('相册'), findsOneWidget);
    expect(find.text('相机'), findsOneWidget);
    expect(find.text('电话'), findsOneWidget);
    expect(
      tester
          .widgetList<ChatMenuIcon>(find.byType(ChatMenuIcon))
          .map((icon) => icon.symbol),
      ChatMenuSymbol.values,
    );
    for (final icon in find.byType(ChatMenuIcon).evaluate()) {
      final container = tester.widget<Container>(find
          .ancestor(
              of: find.byWidget(icon.widget), matching: find.byType(Container))
          .first);
      expect((container.decoration as BoxDecoration).color,
          BingoPalette.chatMenuSurface);
    }

    await tester.tap(find.text('电话'));
    expect(called, isTrue);
  });

  testWidgets('dismisses the more panel when tapping outside', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: Text('聊天区域')),
              MessageInput(
                enabled: true,
                speechGateway: _FakeSpeechGateway(),
                onSend: (_) {},
                onCall: () {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多功能'));
    await tester.pumpAndSettle();
    expect(find.text('相册'), findsOneWidget);

    await tester.tap(find.text('聊天区域'));
    await tester.pumpAndSettle();
    expect(find.text('相册'), findsNothing);

    await tester.tap(find.byTooltip('更多功能'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('键盘输入'));
    await tester.pumpAndSettle();
    expect(find.text('相册'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  for (final groupMenu in [false, true]) {
    testWidgets('sticker panel dismisses outside in group=$groupMenu',
        (tester) async {
      var outsideTaps = 0;
      final sent = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        Expanded(
            child: Center(
                child: TextButton(
                    onPressed: () => outsideTaps++,
                    child: const Text('聊天区域')))),
        MessageInput(
            enabled: true,
            referenceStyle: true,
            initialVoiceMode: false,
            groupMenu: groupMenu,
            speechGateway: _FakeSpeechGateway(),
            onSend: sent.add,
            onCall: () {})
      ]))));
      await tester.tap(find.byTooltip('表情'));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPanel), findsOneWidget);
      // Interacting inside the panel must still allow sending several stickers.
      await tester.tap(find.bySemanticsLabel(RegExp('发送表情：.*')).first);
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(find.byType(StickerPanel), findsOneWidget);
      await tester.tap(find.text('聊天区域'));
      await tester.pumpAndSettle();
      expect(outsideTaps, 1);
      expect(find.byType(StickerPanel), findsNothing);
      // Its own button toggles closed rather than closing and reopening.
      await tester.tap(find.byTooltip('表情'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('表情'));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPanel), findsNothing);
      await tester.tap(find.byTooltip('表情'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多功能'));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPanel), findsNothing);
      expect(find.text(groupMenu ? '照片' : '相册'), findsOneWidget);
      await tester.tap(find.byTooltip('表情'));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPanel), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPanel), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('switches the trailing action between more and send',
      (tester) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageInput(
            enabled: true,
            speechGateway: _FakeSpeechGateway(),
            onSend: (value) => sent = value,
            onCall: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('更多功能'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

    await tester.tap(find.byTooltip('键盘输入'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('更多功能'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();
    expect(find.byTooltip('更多功能'), findsNothing);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(sent, 'hello');
    expect(find.byTooltip('更多功能'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
  });
}
