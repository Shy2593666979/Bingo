import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/auth/presentation/user_agreement_page.dart';
import 'package:bingo/features/settings/presentation/account_deletion_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('privacy includes approved content and working email action',
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
        MaterialApp(theme: buildBingoTheme(), home: const PrivacyPolicyPage()));
    expect(find.text('把隐私，说清楚'), findsOneWidget);
    expect(find.textContaining('尚未生效'), findsNothing);
    expect(find.textContaining('火山引擎'), findsNothing);
    expect(find.textContaining('阅读不等于授权'), findsNothing);
    await tester.tap(find.text('07  政策更新与联系'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('bingo202610@126.com'));
    await tester.tap(find.text('bingo202610@126.com'));
    await tester.pumpAndSettle();
    expect(calls, ['openPrivacyEmail']);
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets(
        'direct deletion requires confirmation and handles failure: $fails',
        (tester) async {
      final gateway = _DeletionGateway(fails);
      var finished = false;
      await tester.pumpWidget(MaterialApp(
          theme: buildBingoTheme(),
          home: AccountDeletionPage(
              gateway: gateway,
              onDeleted: () async {
                finished = true;
              })));
      final button = find.widgetWithText(FilledButton, '注销账号');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(find.textContaining('通过邮件'), findsNothing);
      await tester.scrollUntilVisible(find.byType(CheckboxListTile), 300);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('暂不注销'));
      await tester.pumpAndSettle();
      expect(gateway.calls, 0);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认注销'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(gateway.calls, 1);
      expect(finished, !fails);
      if (fails) {
        expect(find.text('服务器暂时不可用'), findsOneWidget);
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _DeletionGateway implements AccountDeletionGateway {
  _DeletionGateway(this.fails);
  final bool fails;
  int calls = 0;
  @override
  Future<void> deleteAccount() async {
    calls++;
    if (fails) throw const ApiException('服务器暂时不可用');
  }
}
