import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/sleep_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements MomentGateway {
  _Gateway({this.failSecond = false});
  final bool failSecond;
  final requests = <Map<String, Object>>[];
  @override
  Future<void> cancelMoment(String runId) async {}
  @override
  Stream<ChatStreamEvent> finishMoment(
          {required String conversationId,
          required String sessionId,
          required String feature,
          required String summary}) =>
      throw UnimplementedError();
  @override
  Stream<ChatStreamEvent> generateMoment(
      {required String conversationId,
      required String runId,
      required String mode,
      required String previous,
      required int seconds,
      required double charactersPerSecond,
      required bool closing}) async* {
    requests
        .add({'previous': previous, 'seconds': seconds, 'closing': closing});
    if (failSecond && requests.length == 2) throw StateError('prefetch failed');
    yield const ChatSegment('小兔子沿着月光回家。');
    yield ChatAudio(Uint8List(300 * 48000));
    yield const ChatAudioDone();
  }
}

void main() {
  testWidgets('a failed prefetch keeps the current story playing',
      (tester) async {
    final gateway = _Gateway(failSecond: true);
    final session = SleepSession(
        gateway: gateway,
        conversationId: 'conversation',
        mode: 'story',
        minutes: 10,
        onEnded: (_, __) async {});
    session.start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(session.active, isTrue);
    expect(session.paused, isFalse);
    expect(session.error, contains('讲完当前段'));
    await session.pause();
    session.resume();
    expect(session.paused, isFalse);
    session.dispose();
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = <MethodCall>[];
  const channel = MethodChannel('bingo/device_tools');
  setUp(() {
    native.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      native.add(call);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  testWidgets(
      'prefetch retains story, closes final part and feeds small paced audio',
      (tester) async {
    final gateway = _Gateway();
    var now = DateTime(2026, 10, 7);
    final ended = <int>[];
    final session = SleepSession(
        gateway: gateway,
        conversationId: 'conversation',
        mode: 'story',
        minutes: 10,
        now: () => now,
        onEnded: (automatic, seconds) async {
          ended.add(seconds);
        });
    session.start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(gateway.requests.length, 2);
    expect(gateway.requests.first['seconds'], 300);
    expect(gateway.requests.last['previous'], contains('小兔子'));
    expect(gateway.requests.last['closing'], true);
    expect(ended, isEmpty);
    expect(
        native
            .where((call) => call.method == 'playReplyAudio')
            .every((call) => (call.arguments as Uint8List).length <= 9600),
        isTrue);
    await session.pause();
    now = now.add(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(session.remainingSeconds, 600);
    session.resume();
    now = now.add(const Duration(minutes: 10));
    await tester.pump(const Duration(milliseconds: 200));
    expect(ended, [600]);
    await session.end();
    expect(ended, [600]);
    session.dispose();
  });

  testWidgets('manual end records once; quiet companion uses no model',
      (tester) async {
    final gateway = _Gateway();
    var now = DateTime(2026, 10, 7);
    final ended = <bool>[];
    final session = SleepSession(
        gateway: gateway,
        conversationId: 'conversation',
        mode: 'quiet',
        minutes: 20,
        now: () => now,
        onEnded: (automatic, seconds) async {
          ended.add(automatic);
          expect(seconds, 12);
        });
    session.start();
    now = now.add(const Duration(seconds: 12));
    await session.end();
    await session.end();
    expect(gateway.requests, isEmpty);
    expect(ended, [false]);
    session.dispose();
  });
}
