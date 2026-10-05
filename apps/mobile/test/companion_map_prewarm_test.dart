import 'package:bingo/features/chat/presentation/widgets/companion_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bingo/map_capability');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('prewarm requests only map initialization, not device location',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await prewarmCompanionMap();
    expect(calls, ['prewarm']);
  });

  test('unsupported or failed prewarm does not interrupt menu opening',
      () async {
    await prewarmCompanionMap();
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    await prewarmCompanionMap();
  });
}
