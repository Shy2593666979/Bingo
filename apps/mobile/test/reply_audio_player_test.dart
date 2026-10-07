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
}
