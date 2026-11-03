import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/bingo_confirm_dialog.dart';
import 'package:bingo/features/group_chat/presentation/create_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'confirmation distinguishes cancel, dismiss and confirm on a narrow screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final results = <bool?>[];
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async => results.add(
                        await showBingoConfirmDialog(context,
                            title: '确认注销账号？',
                            message: '账号、对话与自定义搭子将被删除，注销后无法恢复。',
                            confirmLabel: '确认注销',
                            cancelLabel: '暂不注销',
                            destructive: true)),
                    child: const Text('打开'))))));
    Future<void> open() async {
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
    }

    await open();
    final cancel = find.widgetWithText(TextButton, '暂不注销');
    final confirm = find.widgetWithText(FilledButton, '确认注销');
    expect(tester.getSize(cancel).width, tester.getSize(confirm).width);
    expect(tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
        Colors.white);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    await open();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await open();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(results, [false, null, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'creation entries remain reachable with large text on a narrow screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: CreateCenterPage(
            onCreateRole: () async => opened.add('role'),
            onCreateGroup: () async => opened.add('group'),
            onPublish: () async => opened.add('share'))));
    await tester.pumpAndSettle();
    for (final text in ['开始创建', '创建群聊', '分享搭子']) {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }
    expect(opened, ['role', 'group', 'share']);
    expect(tester.takeException(), isNull);
  });
}
