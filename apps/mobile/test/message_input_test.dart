import 'dart:async';

import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
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

    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard_alt_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(sent, 'hello');
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
  });
}
