import 'dart:async';

import 'package:bingo/features/chat/presentation/bubble_pacer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interval uses character count, jitter and final bounds', () {
    expect(BubblePacer.interval('早呀', 0), const Duration(seconds: 1));
    expect(
        BubblePacer.interval('字' * 20, 0), const Duration(milliseconds: 1190));
    expect(
        BubblePacer.interval('字' * 20, 1), const Duration(milliseconds: 1610));
    expect(BubblePacer.interval('字' * 100, 1), const Duration(seconds: 3));
    expect(BubblePacer.interval('😀' * 20, 0.5),
        const Duration(milliseconds: 1400));
  });

  testWidgets('first bubble is immediate and later bubbles queue in order',
      (tester) async {
    final pacer = BubblePacer(random: () => 0.5);
    final visible = <String>[];
    pacer.enqueue('早呀', () => visible.add('早呀'));
    pacer.enqueue('昨晚睡得怎么样？', () => visible.add('昨晚睡得怎么样？'));
    pacer.enqueue('今天有什么安排？', () => visible.add('今天有什么安排？'));
    expect(visible, ['早呀']);
    expect(pacer.isPending, isTrue);
    await tester.pump(const Duration(milliseconds: 999));
    expect(visible, ['早呀']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(visible, ['早呀', '昨晚睡得怎么样？']);
    await tester.pump(const Duration(seconds: 2));
    expect(visible, ['早呀', '昨晚睡得怎么样？', '今天有什么安排？']);
    expect(pacer.isPending, isFalse);
    await pacer.drained;
    pacer.reset();
  });

  testWidgets('reset cancels pending reveals and releases drain waiters',
      (tester) async {
    final pacer = BubblePacer(random: () => 0.5);
    final visible = <String>[];
    pacer.enqueue('第一条', () => visible.add('第一条'));
    pacer.enqueue('旧回复', () => visible.add('旧回复'));
    final drained = pacer.drained;
    pacer.reset();
    await drained;
    pacer.enqueue('新回复', () => visible.add('新回复'));
    await tester.pump(const Duration(seconds: 3));
    expect(visible, ['第一条', '新回复']);
    pacer.reset();
  });

  test('existing network wait does not add another pause', () async {
    final pacer = BubblePacer(random: () => 0.5);
    final visible = <String>[];
    pacer.enqueue('早呀', () => visible.add('早呀'));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    pacer.enqueue('第二条', () => visible.add('第二条'));
    expect(visible, ['早呀', '第二条']);
    expect(pacer.isPending, isFalse);
    pacer.reset();
  });

  testWidgets('delay uses the upcoming bubble, not the previous bubble',
      (tester) async {
    final pacer = BubblePacer(random: () => 0.5);
    final visible = <String>[];
    pacer.enqueue('字' * 100, () => visible.add('长句'));
    pacer.enqueue('短句', () => visible.add('短句'));
    await tester.pump(const Duration(milliseconds: 999));
    expect(visible, ['长句']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(visible, ['长句', '短句']);
    pacer.reset();
  });

  testWidgets('long playback consumes the interval without another pause',
      (tester) async {
    var elapsed = Duration.zero;
    final played = Completer<void>();
    final visible = <String>[];
    final pacer =
        BubblePacer(random: () => 0.5, elapsedSinceReveal: () => elapsed);
    pacer.enqueue('第一条', () => visible.add('第一条'), played: played.future);
    pacer.enqueue('第二条', () => visible.add('第二条'));
    elapsed = const Duration(seconds: 4);
    await tester.pump(elapsed);
    expect(visible, ['第一条']);
    played.complete();
    await tester.pump();
    expect(visible, ['第一条', '第二条']);
    await pacer.drained;
    pacer.reset();
  });

  testWidgets('late playback completion cannot reveal a cancelled turn',
      (tester) async {
    final played = Completer<void>();
    final visible = <String>[];
    final pacer = BubblePacer(random: () => 0.5);
    pacer.enqueue('第一条', () => visible.add('第一条'), played: played.future);
    pacer.enqueue('旧消息', () => visible.add('旧消息'));
    final drained = pacer.drained;
    pacer.reset();
    await drained;
    pacer.enqueue('新消息', () => visible.add('新消息'));
    played.complete();
    await tester.pump(const Duration(seconds: 4));
    expect(visible, ['第一条', '新消息']);
    pacer.reset();
  });
}
