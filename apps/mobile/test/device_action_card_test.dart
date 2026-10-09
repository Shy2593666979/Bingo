import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/widgets/device_action_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in {
    'pending': '确认创建',
    'succeeded': '创建成功',
    'rejected': '已拒绝 · 闹钟未创建',
    'submitted': '已交给系统时钟 · 待系统确认',
    'failed': '创建失败'
  }.entries) {
    testWidgets('alarm card keeps ${entry.key} visible', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DeviceActionCard(
        action: DeviceAction(
            id: 'alarm',
            tool: 'device_alarm_create',
            title: '创建闹钟',
            description: '明天 07:00 · 起床',
            arguments: const {},
            status: entry.key,
            result: entry.key == 'failed' ? '没有权限' : null),
        onApprove: () {},
        onReject: () {},
      ))));
      expect(find.text('明天 07:00 · 起床'), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('创建闹钟'), findsNothing);
      expect(find.text('确认创建'),
          entry.key == 'pending' ? findsOneWidget : findsNothing);
      expect(find.text('拒绝'),
          entry.key == 'pending' ? findsOneWidget : findsNothing);
      if (entry.key == 'failed') expect(find.text('没有权限'), findsOneWidget);
    });
  }

  testWidgets('alarm note shows time and uses red reject and mint confirm',
      (tester) async {
    var approvals = 0;
    var rejections = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DeviceActionCard(
                action: const DeviceAction(
                    id: 'alarm',
                    tool: 'device_alarm_create',
                    title: '创建闹钟',
                    description: '2099-01-01 07:00 · 起床',
                    arguments: {
                      'scheduled_at': '2099-01-01T07:00:00',
                      'label': '起床',
                      'recurrence': 'weekdays'
                    }),
                onApprove: () => approvals++,
                onReject: () => rejections++))));
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('2099-01-01 · 起床 · 工作日'), findsOneWidget);
    expect(find.text('创建闹钟'), findsNothing);
    final reject = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(reject.style!.foregroundColor!.resolve({}), const Color(0xFFB5403C));
    final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
        confirm.style!.backgroundColor!.resolve({}), const Color(0xFFBFE5D4));
    await tester.tap(find.text('拒绝'));
    await tester.tap(find.text('确认创建'));
    expect(rejections, 1);
    expect(approvals, 1);
    expect(tester.takeException(), isNull);
  });
}
