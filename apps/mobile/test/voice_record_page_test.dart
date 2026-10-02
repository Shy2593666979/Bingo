import 'dart:typed_data';

import 'package:bingo/features/auth/presentation/voice_record_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'silence and constant samples are rejected without rejecting quiet signal',
      () {
    expect(recordingHasSignal(Uint8List(32000)), isFalse);
    expect(recordingHasSignal(Uint8List.fromList([1, 0, 1, 0])), isFalse);
    expect(recordingHasSignal(Uint8List.fromList([20, 0, 236, 255])), isTrue);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = MethodChannel('bingo/device_tools');
  const audio = MethodChannel('bingo/audio_stream');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(device, (_) async => null);
    messenger.setMockMethodCallHandler(audio, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(device, null);
    messenger.setMockMethodCallHandler(audio, null);
  });

  Future<void> emitRecording(WidgetTester tester, int seconds,
      {bool silent = false}) async {
    final pcm = Uint8List(32000 * seconds);
    if (!silent) ByteData.sublistView(pcm).setInt16(0, 1000, Endian.little);
    await messenger.handlePlatformMessage('bingo/audio_stream',
        const StandardMethodCodec().encodeSuccessEnvelope(pcm), (_) {});
    await tester.pump();
  }

  testWidgets('short recording shows toast and cannot be submitted',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: VoiceRecordPage()));
    await tester.tap(find.text('开始录音'));
    await tester.pumpAndSettle();
    await emitRecording(tester, 14);
    expect(find.text('14 秒'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('结束录音'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('录音时间太短，请重新录制'), findsOneWidget);
    expect(find.text('使用这段录音复刻'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('silent recording cannot be submitted even when long enough',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: VoiceRecordPage()));
    await tester.tap(find.text('开始录音'));
    await tester.pumpAndSettle();
    await emitRecording(tester, 20, silent: true);
    await tester.runAsync(() async {
      await tester.tap(find.text('结束录音'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('录音没有检测到声音，请检查麦克风后重新录制'), findsOneWidget);
    expect(find.text('使用这段录音复刻'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('valid recording requires consent before returning audio',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Uint8List? returned;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        returned = await Navigator.of(context).push<Uint8List>(
                            MaterialPageRoute(
                                builder: (_) => const VoiceRecordPage()));
                      },
                      child: const Text('录音')),
                ))));
    await tester.tap(find.text('录音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始录音'));
    await tester.pumpAndSettle();
    await emitRecording(tester, 20);
    expect(find.text('20 秒'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('结束录音'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.ensureVisible(find.text('使用这段录音复刻'));
    await tester.pumpAndSettle();
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '使用这段录音复刻'));
    expect(button.onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用这段录音复刻'));
    await tester.pumpAndSettle();
    expect(returned?.length, 32000 * 20);
  });
}
