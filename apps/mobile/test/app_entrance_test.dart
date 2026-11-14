import 'package:bingo/core/widgets/app_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.onStart);
  final VoidCallback onStart;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) => const Text('首页');
}

void main() {
  testWidgets('mounts immediately and does not replay on data updates',
      (tester) async {
    var requests = 0;
    Widget page() =>
        MaterialApp(home: AppEntrance(child: _Probe(() => requests++)));
    await tester.pumpWidget(page());
    expect(requests, 1);
    final opacity = find.descendant(
        of: find.byType(AppEntrance), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<Opacity>(opacity).opacity, greaterThan(.5));
    expect(tester.widget<Opacity>(opacity).opacity, lessThan(1));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    await tester.pumpWidget(page());
    expect(requests, 1);
    expect(tester.widget<Opacity>(opacity).opacity, 1);
  });

  testWidgets('respects reduced motion', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: AppEntrance(child: Text('首页')))));
    expect(find.text('首页'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });
}
