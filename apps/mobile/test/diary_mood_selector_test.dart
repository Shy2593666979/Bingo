import 'package:bingo/features/chat/presentation/widgets/diary_mood_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets('four painted moods remain in one row at text scale $scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var selected = '还不错';
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Padding(
                      padding: const EdgeInsets.all(42),
                      child: StatefulBuilder(
                          builder: (context, setState) => DiaryMoodSelector(
                              value: selected,
                              onChanged: (value) =>
                                  setState(() => selected = value))))))));
      final positions = DiaryMoodSelector.moods
          .map((mood) =>
              tester.getTopLeft(find.byKey(ValueKey('diary-mood-$mood'))))
          .toList();
      expect(positions.map((position) => position.dy).toSet(), hasLength(1));
      expect(positions[0].dx, lessThan(positions[1].dx));
      expect(positions[2].dx, lessThan(positions[3].dx));
      expect(
          find.descendant(
              of: find.byType(DiaryMoodSelector),
              matching: find.byType(CustomPaint)),
          findsNWidgets(4));
      await tester.tap(find.text('很开心'));
      await tester.pump();
      expect(selected, '很开心');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabled mood selection does not change its value',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home:
            Scaffold(body: DiaryMoodSelector(value: '还不错', onChanged: null))));
    await tester.tap(find.text('有点累'));
    await tester.pump();
    expect(
        tester.widget<DiaryMoodSelector>(find.byType(DiaryMoodSelector)).value,
        '还不错');
    expect(tester.takeException(), isNull);
  });
}
