import 'package:bingo/core/widgets/center_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('center toast is centered and lasts two seconds', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCenterToast(context, '测试提示'),
            child: const Text('显示'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示'));
    await tester.pump();

    final toast = find.text('测试提示');
    expect(toast, findsOneWidget);
    expect(tester.getCenter(toast).dy, closeTo(300, 30));

    await tester.pump(const Duration(milliseconds: 1999));
    expect(toast, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(toast, findsNothing);
  });
}
