import 'package:bingo/shared/widgets/speaking_wave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('playback bars animate without changing the indicator size',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(child: SpeakingWave(color: Colors.green))));
    final bar = find.byKey(const ValueKey('speaking-wave-bar-0'));
    final initial = tester.getSize(bar).height;
    final frame = tester.getSize(find.byType(SpeakingWave));
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getSize(bar).height, isNot(initial));
    expect(tester.getSize(find.byType(SpeakingWave)), frame);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion stops the playback animation', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: SpeakingWave(color: Colors.green))));
    final bar = find.byKey(const ValueKey('speaking-wave-bar-0'));
    final initial = tester.getSize(bar);
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getSize(bar), initial);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
