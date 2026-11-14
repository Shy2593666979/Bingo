import 'package:bingo/core/widgets/startup_reveal.dart';
import 'package:bingo/core/design/bingo_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads underneath the animated cover until explicitly ready',
      (tester) async {
    late VoidCallback ready;
    var builds = 0;
    await tester.pumpWidget(MaterialApp(home: StartupReveal(builder: (onReady) {
      builds++;
      ready = onReady;
      return const Scaffold(body: Text('已加载的首页'));
    })));
    expect(builds, 1);
    expect(find.text('已加载的首页'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(BingoWordmark), findsOneWidget);
    ready();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byType(BingoWordmark), findsNothing);
    expect(find.text('已加载的首页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    ready();
    expect(tester.takeException(), isNull);
  });
}
