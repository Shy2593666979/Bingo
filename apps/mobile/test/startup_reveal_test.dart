import 'package:bingo/core/widgets/startup_reveal.dart';
import 'package:bingo/core/widgets/startup_brand_scene.dart';
import 'package:bingo/core/design/bingo_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('logo stays centered and never moves as the tagline appears',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StartupBrandScene()));
    final logo = find.byType(BingoWordmark);
    final before = tester.getRect(logo);
    final scene = tester.getRect(find.byType(StartupBrandScene));
    expect(before.center, scene.center);
    expect(before.size, const Size(174, 174));
    for (final duration in [900, 900, 900]) {
      await tester.pump(Duration(milliseconds: duration));
      expect(tester.getRect(logo), before);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Chinese tagline reveals in order with punctuation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StartupBrandScene()));
    double opacity(String key) =>
        tester.widget<Opacity>(find.byKey(ValueKey(key))).opacity;
    expect(find.text('每个人，'), findsOneWidget);
    expect(find.text('都可以成为你的搭子。'), findsOneWidget);
    expect(opacity('startup-tagline-first'), 0);
    expect(opacity('startup-tagline-second'), 0);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(opacity('startup-tagline-first'), greaterThan(0));
    expect(opacity('startup-tagline-second'), 0);
    await tester.pump(const Duration(milliseconds: 1700));
    expect(opacity('startup-tagline-first'), 1);
    expect(opacity('startup-tagline-second'), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows the complete tagline immediately',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: StartupBrandScene(),
    )));
    for (final key in ['startup-tagline-first', 'startup-tagline-second']) {
      expect(tester.widget<Opacity>(find.byKey(ValueKey(key))).opacity, 1);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(find.byType(BingoWordmark), findsNothing);
    expect(find.text('已加载的首页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    ready();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached data waits for the intro while home is already mounted',
      (tester) async {
    late VoidCallback ready;
    await tester.pumpWidget(MaterialApp(home: StartupReveal(builder: (onReady) {
      ready = onReady;
      return const Scaffold(body: Text('预加载首页'));
    })));
    ready();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.byType(StartupBrandScene), findsOneWidget);
    expect(find.text('预加载首页'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(find.byType(StartupBrandScene), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
