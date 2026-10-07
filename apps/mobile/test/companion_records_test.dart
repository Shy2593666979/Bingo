import 'dart:convert';
import 'package:bingo/features/chat/presentation/companion_records_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bingo/local_chat');
  const device = MethodChannel('bingo/device_tools');
  final saved = <String, String>{};
  final reminderCalls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    saved.clear();
    reminderCalls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final prefix = '${args['user_id']}:';
      if (call.method == 'listCompanionData') {
        return {
          for (final record
              in saved.entries.where((record) => record.key.startsWith(prefix)))
            record.key.substring(prefix.length): record.value,
        };
      }
      final key = '$prefix${args['key']}';
      if (call.method == 'readCompanionData') return saved[key];
      if (call.method == 'writeCompanionData') {
        saved[key] = args['data'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(device, (call) async {
      reminderCalls.add(call);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(device, null);
  });

  void seed(String user, String conversation, String kind, String text,
      {String status = 'waiting', String partner = '甜甜'}) {
    saved['$user:moments:$conversation:$kind'] = jsonEncode({
      'partner_name': partner,
      'session_id': 'preserve-session',
      'summary_sent': true,
      'entries': [
        {
          'id': '$conversation-$kind',
          'text': text,
          'status': status,
          'mood': '还不错',
          'time': DateTime.now().add(const Duration(days: 1)).toIso8601String()
        }
      ],
    });
  }

  testWidgets(
      'records aggregate partners, isolate accounts and edit diary locally',
      (tester) async {
    seed('user', 'first', 'diary', '今天走了一段路');
    seed('user', 'second', 'diary', '今天读了一本书', partner: '暖暖');
    seed('other', 'private', 'diary', '其他账号的私密内容');
    await tester.pumpWidget(
        const MaterialApp(home: CompanionRecordsPage(userId: 'user')));
    await tester.pumpAndSettle();
    expect(find.text('今天走了一段路'), findsOneWidget);
    expect(find.text('今天读了一本书'), findsOneWidget);
    expect(find.text('其他账号的私密内容'), findsNothing);
    await tester.tap(find.text('今天走了一段路'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '修改后的小记正文');
    await tester.tap(find.text('有点累'));
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(find.text('修改后的小记正文'), findsOneWidget);
    final data = jsonDecode(saved['user:moments:first:diary']!) as Map;
    expect(data['session_id'], 'preserve-session');
    expect(data['summary_sent'], true);
    expect(((data['entries'] as List).single as Map)['mood'], '有点累');
    expect(reminderCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'promise status tabs manage completion and cancel native reminder',
      (tester) async {
    seed('user', 'first', 'promise', '散步');
    seed('user', 'second', 'promise', '读书', status: 'completed');
    seed('user', 'third', 'promise', '旅行', status: 'skipped');
    await tester.pumpWidget(const MaterialApp(
        home: CompanionRecordsPage(
            userId: 'user', initialKind: CompanionRecordKind.promise)));
    await tester.pumpAndSettle();
    expect(find.text('散步'), findsOneWidget);
    expect(find.text('读书'), findsNothing);
    await tester.tap(find.text('散步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成了'));
    await tester.pumpAndSettle();
    expect(find.text('散步'), findsNothing);
    expect(reminderCalls.single.method, 'cancelCompanionReminder');
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('散步'), findsOneWidget);
    expect(find.text('读书'), findsOneWidget);
    await tester.tap(find.text('已取消'));
    await tester.pumpAndSettle();
    expect(find.text('旅行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scoped shortcut and focus sleep histories remain available',
      (tester) async {
    seed('user', 'first', 'focus', '专注了25分钟');
    seed('user', 'second', 'focus', '不应展示的另一位伙伴');
    seed('user', 'first', 'sleep', '陪伴了10分钟');
    await tester.pumpWidget(const MaterialApp(
        home: CompanionRecordsPage(
            userId: 'user',
            conversationId: 'first',
            initialKind: CompanionRecordKind.focus)));
    await tester.pumpAndSettle();
    expect(find.text('专注了25分钟'), findsOneWidget);
    expect(find.text('不应展示的另一位伙伴'), findsNothing);
    await tester.tap(find.text('入睡'));
    await tester.pumpAndSettle();
    expect(find.text('陪伴了10分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
