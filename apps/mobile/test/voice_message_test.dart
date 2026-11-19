import 'dart:async';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/message_presentation_store.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/widgets/local_message_view.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class VoiceTestGateway implements ChatGateway, SpeechGateway {
  String? sent;
  String recognized = '今天想一起散步';
  bool failRecognition = false;
  Completer<String>? pendingRecognition;
  @override
  Future<String> transcribe(Uint8List wavAudio) async {
    if (failRecognition) throw StateError('ASR unavailable');
    return pendingRecognition == null ? recognized : pendingRecognition!.future;
  }

  @override
  Stream<ChatStreamEvent> send(
      {String? conversationId,
      required String content,
      required String runId,
      String? supersedesRunId,
      List<ChatImageUpload> images = const []}) async* {
    sent = content;
    yield ChatStarted('conversation',
        userMessageId: 'saved-voice', createdAt: DateTime.utc(2026));
    yield const ChatSegment('好呀，一起走走。');
    yield const ChatFinished('reply');
  }
}

class OrderedVoiceGateway extends VoiceTestGateway {
  final queries = <String>[];
  final conversationIds = <String?>[];
  @override
  Stream<ChatStreamEvent> send(
      {String? conversationId,
      required String content,
      required String runId,
      String? supersedesRunId,
      List<ChatImageUpload> images = const []}) async* {
    final index = queries.length;
    queries.add(content);
    conversationIds.add(conversationId);
    yield ChatStarted('conversation',
        userMessageId: 'user-$index', createdAt: DateTime.utc(2026));
    yield const ChatSegment('收到。');
    yield ChatFinished('reply-$index');
  }
}

class LateRealtimeVoiceGateway extends VoiceTestGateway
    implements RealtimeSpeechGateway {
  final connection = Completer<RealtimeTranscriptionSession>();
  @override
  Future<RealtimeTranscriptionSession> startRealtimeTranscription() =>
      connection.future;
}

class BufferedVoiceSession implements RealtimeTranscriptionSession {
  var bytes = 0;
  @override
  void addAudio(Uint8List pcmAudio) {
    bytes += pcmAudio.length;
  }

  @override
  Future<String> finish() async => bytes > 0 ? '缓冲音频已识别' : '';
  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = MethodChannel('bingo/device_tools');
  const audio = MethodChannel('bingo/audio_stream');
  final disk = <String, String>{}, recordings = <String, Uint8List>{};
  final calls = <MethodCall>[];
  var failSave = false;
  Completer<void>? playback;
  setUp(() {
    MessagePresentationStore.platformAvailable = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(MessagePresentationStore.channel,
        (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final account = args['account'] as String;
      switch (call.method) {
        case 'load':
          return disk[account];
        case 'save':
          if (failSave) throw PlatformException(code: 'disk_full');
          disk[account] = args['data'] as String;
          return null;
        case 'writeVoice':
          recordings['$account:${args['key']}'] = args['bytes'] as Uint8List;
          return null;
        case 'readVoice':
          return recordings['$account:${args['key']}'];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(device, (call) async {
      calls.add(call);
      if (call.method == 'playPreviewAudio') {
        playback = Completer<void>();
        await playback!.future;
      }
      if (call.method == 'stopPreviewAudio' && playback?.isCompleted == false) {
        playback!.complete();
      }
      return null;
    });
    messenger.setMockMethodCallHandler(audio, (_) async => null);
  });
  tearDown(() {
    failSave = false;
    MessagePresentationStore.platformAvailable = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [MessagePresentationStore.channel, device, audio]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    calls.clear();
  });

  test('voice sends only transcript and survives server ID replacement',
      () async {
    final gateway = VoiceTestGateway();
    final chat = ChatController(gateway: gateway);
    await chat.bindAccount('voice-sender');
    final bytes = Uint8List.fromList(List.filled(32044, 1));
    await chat.sendVoice(RecordedVoice('今天想一起散步', bytes, 1000));
    expect(gateway.sent, '用户发送的语音转文字后：今天想一起散步');
    final store = MessagePresentationStore.forAccount('voice-sender');
    expect(store.item('message:saved-voice')['voice'], true);
    expect(await store.readVoice('message:saved-voice'), bytes);
    await store.update('message:saved-voice', {'hidden': true});
    expect(store.item('message:saved-voice')['hidden'], true);
    expect(chat.messages.first.content, '今天想一起散步');
    expect(disk['voice-sender'], contains('hidden'));
    MessagePresentationStore.resetMemory();
    final reopened = MessagePresentationStore.forAccount('voice-sender');
    await reopened.load();
    expect(reopened.item('message:saved-voice')['hidden'], true);
    expect(reopened.item('message:saved-voice')['voice'], true);
    final other = MessagePresentationStore.forAccount('different-account');
    await other.load();
    expect(other.item('message:saved-voice'), isEmpty);
    chat.dispose();
  });

  test('empty voice is sent with context while ordinary text stays unchanged',
      () async {
    final gateway = VoiceTestGateway();
    final chat = ChatController(gateway: gateway);
    await chat.bindAccount('empty-voice-sender');
    await chat.sendVoice(RecordedVoice('', Uint8List(32044), 1000));
    expect(gateway.sent, '用户发送的语音转文字后：（未识别到文字）');
    expect(
        MessagePresentationStore.forAccount('empty-voice-sender')
            .item('message:saved-voice')['voice'],
        true);
    await chat.send('普通文字');
    expect(gateway.sent, '普通文字');
    chat.dispose();
  });

  test(
      'voice is visible before ASR completes and later input preserves send order',
      () async {
    final gateway = OrderedVoiceGateway();
    final chat = ChatController(gateway: gateway);
    await chat.bindAccount('background-asr');
    final recognition = Completer<String>();
    final first = chat.sendVoice(RecordedVoice('', Uint8List(32044), 1000,
        transcribe: () => recognition.future));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(chat.messages.single.content, '[语音]');
    final voiceId = chat.messages.single.id;
    final store = MessagePresentationStore.forAccount('background-asr');
    expect(store.item('message:$voiceId')['voice'], true);
    expect(store.item('message:$voiceId')['transcription_pending'], true);
    expect(gateway.queries, isEmpty);
    final second = chat.send('接着说');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(chat.messages.where((m) => m.content == '接着说'), hasLength(1));
    expect(gateway.queries, isEmpty);
    recognition.complete('今天想一起散步');
    await Future.wait([first, second]);
    expect(gateway.queries, ['用户发送的语音转文字后：今天想一起散步', '接着说']);
    expect(gateway.conversationIds, [null, 'conversation']);
    expect(store.item('message:user-0')['transcription_pending'], false);
    expect(store.item('message:user-0')['transcript'], '今天想一起散步');
    chat.dispose();
  });

  testWidgets(
      'voice plays original WAV, converts in place, copies and deletes locally',
      (tester) async {
    final store = MessagePresentationStore.forAccount('voice-widget');
    final wav = Uint8List.fromList(List.filled(64044, 2));
    await store.saveVoice('voice', RecordedVoice('今天想一起散步', wav, 2000));
    Widget view() => MaterialApp(
        home: Scaffold(
            body: LocalMessageView(
                account: 'voice-widget',
                messageKey: 'voice',
                text: '今天想一起散步',
                isUser: true,
                builder: (voice) => voice ?? const Text('今天想一起散步'))));
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.text('今天想一起散步'), findsNothing);
    expect(find.text('2″'), findsOneWidget);
    await tester.tap(find.text('2″'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.last.method, 'playPreviewAudio');
    expect(calls.last.arguments, wav);
    await tester.tap(find.text('2″'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'stopPreviewAudio');
    await tester.longPress(find.text('2″'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final menu =
        tester.getRect(find.byKey(const ValueKey('bubble-message-menu')));
    expect(menu.height, lessThan(80));
    expect(menu.top, lessThan(150));
    await tester.tap(find.text('转文字'));
    await tester.pumpAndSettle();
    expect(find.text('今天想一起散步'), findsOneWidget);
    expect(find.text('2″'), findsOneWidget);
    await tester.longPress(find.text('2″'));
    await tester.pumpAndSettle();
    expect(find.text('取消转文字'), findsOneWidget);
    expect(find.text('转文字'), findsNothing);
    await tester.tap(find.text('取消转文字'));
    await tester.pumpAndSettle();
    expect(find.text('今天想一起散步'), findsNothing);
    expect(find.text('2″'), findsOneWidget);
    await tester.longPress(find.text('2″'));
    await tester.pumpAndSettle();
    expect(find.text('转文字'), findsOneWidget);
    await tester.tap(find.text('转文字'));
    await tester.pumpAndSettle();
    expect(find.text('今天想一起散步'), findsOneWidget);
    await tester.longPress(find.text('2″'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('2″'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('2″'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(find.text('2″'), findsNothing);
  });

  testWidgets('AI text copy and local deletion rollback on failed disk write',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LocalMessageView(
                account: 'ai-delete',
                messageKey: 'ai-reply',
                text: '好呀，一起走走。',
                isUser: false,
                builder: (_) => const Text('好呀，一起走走。')))));
    await tester.pumpAndSettle();
    failSave = true;
    await tester.longPress(find.text('好呀，一起走走。'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('好呀，一起走走。'), findsOneWidget);
    failSave = false;
    await tester.longPress(find.text('好呀，一起走走。'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('好呀，一起走走。'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('hold recording animates and sends WAV while convert sends text',
      (tester) async {
    RecordedVoice? sentVoice;
    String? sentText;
    final pendingReply = Completer<void>();
    final speech = VoiceTestGateway();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: MessageInput(
                    enabled: true,
                    speechGateway: speech,
                    onCall: () {},
                    onVoiceSend: (voice) async {
                      sentVoice = voice;
                      sentVoice = await voice.resolve();
                      await pendingReply.future;
                    },
                    onSend: (text) => sentText = text)))));
    Future<void> capture(bool convert) async {
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('按住说话')));
      await tester.pump(const Duration(milliseconds: 100));
      final waveform = find.byKey(const ValueKey('recording-waveform'));
      expect(waveform, findsOneWidget);
      final bar =
          find.descendant(of: waveform, matching: find.byType(Container)).first;
      final before = tester.getSize(bar).height;
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.getSize(bar).height, isNot(before));
      unawaited(tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'bingo/audio_stream',
          const StandardMethodCodec()
              .encodeSuccessEnvelope(Uint8List.fromList(List.filled(32000, 4))),
          (_) {}));
      await tester.pump();
      if (convert) {
        await gesture.moveBy(const Offset(110, 0));
        await tester.pump();
      }
      await gesture.up();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.map((c) => c.method), contains('stopAudioCapture'));
      expect(find.byKey(const ValueKey('recording-waveform')), findsNothing);
      await tester.pumpAndSettle();
    }

    speech.pendingRecognition = Completer<String>();
    await capture(false);
    expect(sentText, isNull);
    expect(sentVoice?.text, '');
    expect(sentVoice?.wav.sublist(0, 4), [82, 73, 70, 70]);
    expect(sentVoice?.durationMs, 1000);
    expect(find.text('正在转文字…'), findsNothing);
    expect(find.text('按住说话'), findsOneWidget);
    speech.pendingRecognition!.complete('今天想一起散步');
    await tester.pump();
    expect(sentVoice?.text, '今天想一起散步');
    speech.pendingRecognition = null;
    expect(pendingReply.isCompleted, false);
    pendingReply.complete();
    await tester.pump();
    sentVoice = null;
    await capture(true);
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(sentText, '今天想一起散步');
    expect(sentVoice, isNull);
    speech.recognized = '';
    sentText = null;
    await capture(false);
    expect(sentVoice?.text, '');
    expect(sentText, isNull);
    sentVoice = null;
    await capture(true);
    expect(sentText, isNull);
    expect(sentVoice, isNull);
    expect(find.text('发送'), findsNothing);
    speech.failRecognition = true;
    await capture(false);
    expect(sentVoice?.text, '');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'late realtime ASR receives buffered audio after the voice is submitted',
      (tester) async {
    final speech = LateRealtimeVoiceGateway();
    RecordedVoice? submitted;
    Future<RecordedVoice>? recognition;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessageInput(
      enabled: true,
      speechGateway: speech,
      onCall: () {},
      onSend: (_) {},
      onVoiceSend: (voice) async {
        submitted = voice;
        recognition = voice.resolve();
      },
    ))));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('按住说话')));
    await tester.pump(const Duration(milliseconds: 100));
    unawaited(tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'bingo/audio_stream',
        const StandardMethodCodec().encodeSuccessEnvelope(Uint8List(32000)),
        (_) {}));
    await tester.pump();
    await gesture.up();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(submitted, isNotNull);
    expect(find.text('正在转文字…'), findsNothing);
    expect(speech.connection.isCompleted, false);
    final session = BufferedVoiceSession();
    speech.connection.complete(session);
    await tester.pump();
    final result = await recognition!;
    expect(session.bytes, 32000);
    expect(result.text, '缓冲音频已识别');
    await tester.pumpWidget(const SizedBox());
  });
}
