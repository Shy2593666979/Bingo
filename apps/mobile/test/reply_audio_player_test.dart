import 'dart:async';

import 'package:bingo/features/chat/data/reply_audio_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PCM starts on first chunk, drains, and can still be interrupted',
      () async {
    final calls = <String>[];
    const channel = MethodChannel('bingo/device_tools');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final player = ReplyAudioPlayer();
    await player.stop();
    expect(calls, isEmpty);
    await player.add(Uint8List(4800));
    await player.add(Uint8List(4800));
    await player.finish();
    await player.stop();
    expect(calls, [
      'startReplyAudio',
      'playReplyAudio',
      'playReplyAudio',
      'finishReplyAudio',
      'stopReplyAudio'
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('old drain completion cannot reset a new playback after interruption',
      () async {
    final calls = <String>[];
    final draining = Completer<void>();
    const channel = MethodChannel('bingo/device_tools');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'finishReplyAudio') await draining.future;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final player = ReplyAudioPlayer();
    await player.add(Uint8List(4800));
    final finishing = player.finish();
    await Future<void>.delayed(Duration.zero);
    await player.stop();
    await player.add(Uint8List(4800));
    draining.complete();
    await finishing;
    await player.add(Uint8List(4800));
    expect(calls.where((method) => method == 'startReplyAudio'), hasLength(2));
    await player.stop();
  });
}
