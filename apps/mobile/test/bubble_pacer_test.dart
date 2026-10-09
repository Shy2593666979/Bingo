import 'package:bingo/features/chat/presentation/bubble_pacer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interval uses character count, jitter and final bounds', () {
    expect(BubblePacer.interval('早呀', 0), const Duration(milliseconds: 800));
    expect(
        BubblePacer.interval('字' * 20, 0), const Duration(milliseconds: 1190));
    expect(
        BubblePacer.interval('字' * 20, 1), const Duration(milliseconds: 1610));
    expect(BubblePacer.interval('字' * 100, 1), const Duration(seconds: 2));
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
    await tester.pump(const Duration(milliseconds: 799));
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
    await Future<void>.delayed(const Duration(milliseconds: 850));
    pacer.enqueue('第二条', () => visible.add('第二条'));
    expect(visible, ['早呀', '第二条']);
    expect(pacer.isPending, isFalse);
    pacer.reset();
  });
}
