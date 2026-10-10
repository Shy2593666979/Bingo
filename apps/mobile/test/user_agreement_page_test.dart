import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/presentation/user_agreement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'agreement shows author, section navigation and repository action',
      (tester) async {
    const channel = MethodChannel('bingo/device_tools');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
        MaterialApp(theme: buildBingoTheme(), home: const UserAgreementPage()));
    expect(find.text('遇见之前的小约定'), findsOneWidget);
    expect(find.text('预览草案'), findsNothing);
    expect(find.textContaining('尚未生效'), findsNothing);
    expect(find.textContaining('阅读不等于授权'), findsNothing);
    await tester.tap(find.text('06  变更与反馈'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('田明广'));
    expect(find.text('Mingguang.Tian'), findsOneWidget);
    await tester.ensureVisible(find.text('Shy2593666979 / Bingo'));
    await tester.tap(find.text('Shy2593666979 / Bingo'));
    await tester.pumpAndSettle();
    expect(calls, ['openProjectRepository']);
    expect(tester.takeException(), isNull);
  });
}
