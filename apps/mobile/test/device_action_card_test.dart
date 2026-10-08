import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/widgets/device_action_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in {
    'pending': '待确认',
    'succeeded': '已创建',
    'rejected': '已取消',
    'submitted': '待系统确认',
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
      expect(find.text('创建'),
          entry.key == 'pending' ? findsOneWidget : findsNothing);
      expect(find.text('取消'),
          entry.key == 'pending' ? findsOneWidget : findsNothing);
      if (entry.key == 'failed') expect(find.text('没有权限'), findsOneWidget);
    });
  }
}
