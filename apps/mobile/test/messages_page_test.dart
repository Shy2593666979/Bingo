import 'package:bingo/core/config/app_config.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/conversations/presentation/messages_page.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway extends HttpApiGateway {
  _Gateway()
      : super(
            config: AppConfig(apiBaseUri: Uri.parse('http://localhost:8000')));
  final roles = <Map<String, dynamic>>[
    {
      'id': 'one',
      'name': '女朋友',
      'nickname': '甜甜',
      'builtin': true,
      'message_count': 2,
      'conversation_id': 'c1',
      'last_message': '晚安啦',
      'pinned': true,
      'unread_count': 3,
      'last_message_at': '2026-10-30T03:00:00Z'
    },
    {
      'id': 'two',
      'name': '男朋友',
      'nickname': '暖暖',
      'builtin': true,
      'message_count': 2,
      'conversation_id': 'c2',
      'last_message': '一起去看电影吧',
      'unread_count': 1,
      'last_message_at': '2026-10-30T02:00:00Z'
    },
    {
      'id': 'hidden',
      'name': '同事',
      'builtin': true,
      'message_count': 2,
      'archived': true
    }
  ];
  final group = <String, dynamic>{
    'id': 'group',
    'name': '深夜心情树洞',
    'cover': 'night',
    'members': <Map<String, dynamic>>[],
    'pinned': false,
    'unread_count': 12,
    'last_activity_at': '2026-10-30T01:00:00Z'
  };
  @override
  Future<List<RoleOption>> listRoles() async =>
      roles.map(RoleOption.fromJson).toList();
  @override
  Future<List<ChatGroup>> listGroups() async => [ChatGroup.fromJson(group)];
  @override
  Future<ChatSettings> updateChatSettings(String id,
      {bool? muted, bool? pinned}) async {
    final row = roles.firstWhere((r) => r['conversation_id'] == id);
    if (muted != null) row['muted'] = muted;
    if (pinned != null) row['pinned'] = pinned;
    return ChatSettings(
        muted: row['muted'] == true, pinned: row['pinned'] == true);
  }

  @override
  Future<void> markConversationRead(String id) async =>
      roles.firstWhere((r) => r['conversation_id'] == id)['unread_count'] = 0;
  @override
  Future<void> archiveConversation(String id) async =>
      roles.firstWhere((r) => r['conversation_id'] == id)['archived'] = true;
  @override
  Future<ChatGroup> updateGroup(String id, Map<String, dynamic> data) async {
    group.addAll(data);
    return ChatGroup.fromJson(group);
  }

  @override
  Future<void> readGroup(String id, int seq) async {
    group['unread_count'] = 0;
  }
}

void main() {
  Future<void> size(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('real counts, pinned collapse, filters and new menu callbacks',
      (tester) async {
    await size(tester);
    final gateway = _Gateway();
    int create = 0, role = 0, community = 0, unread = 0;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: Scaffold(
            body: MessagesPage(
                gateway: gateway,
                groups: gateway,
                onRole: (_) async {},
                onGroup: (_) async {},
                onCreate: () => create++,
                onPartners: () {},
                onCreateRole: () => role++,
                onCommunity: () => community++,
                onUnreadChanged: (n) => unread = n))));
    await tester.pumpAndSettle();
    expect(find.text('Bingo 搭子'), findsNothing);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('单聊'), findsOneWidget);
    expect(find.text('群聊'), findsOneWidget);
    expect(unread, 16);
    expect(find.text('置顶聊天'), findsOneWidget);
    expect(tester.getTopLeft(find.text('甜甜')).dy,
        lessThan(tester.getTopLeft(find.text('暖暖')).dy));
    await tester.tap(find.text('置顶聊天'));
    await tester.pumpAndSettle();
    expect(find.text('甜甜'), findsNothing);
    await tester.tap(find.text('群聊'));
    await tester.pumpAndSettle();
    expect(find.text('暖暖'), findsNothing);
    expect(find.text('深夜心情树洞'), findsOneWidget);
    for (final title in ['创建群聊', '创建搭子', '从社区添加']) {
      await tester.tap(find.byTooltip('新建'));
      await tester.pumpAndSettle();
      expect(find.text('创建搭子'), findsOneWidget);
      await tester.tap(find.text(title).last);
      await tester.pumpAndSettle();
    }
    expect([create, role, community], [1, 1, 1]);
    expect(tester.takeException(), isNull);
    gateway.close();
  });
  testWidgets('long press saves read, mute, pin and archive with confirmation',
      (tester) async {
    await size(tester);
    final gateway = _Gateway();
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: Scaffold(
            body: MessagesPage(
                gateway: gateway,
                groups: gateway,
                onRole: (_) async {},
                onGroup: (_) async {},
                onCreate: () {},
                onPartners: () {}))));
    await tester.pumpAndSettle();
    Future<void> action(String title) async {
      await tester.longPress(find.text('暖暖'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title).last);
      await tester.pumpAndSettle();
    }

    await action('标记为已读');
    expect(gateway.roles[1]['unread_count'], 0);
    await action('消息免打扰');
    expect(gateway.roles[1]['muted'], true);
    await action('置顶聊天');
    expect(gateway.roles[1]['pinned'], true);
    await action('删除会话');
    expect(find.text('删除会话？'), findsOneWidget);
    expect(find.textContaining('保留搭子、群聊和聊天记录'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('暖暖'), findsOneWidget);
    await action('删除会话');
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(gateway.roles[1]['archived'], true);
    expect(find.text('暖暖'), findsNothing);
    expect(find.text('全部'), findsOneWidget);
    expect(tester.takeException(), isNull);
    gateway.close();
  });
  testWidgets('large text and long names fit narrow list and both menus',
      (tester) async {
    await size(tester);
    final gateway = _Gateway();
    gateway.roles[0]['nickname'] = '这是一个很长很长的搭子名字';
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        builder: (_, child) => MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 850), textScaler: TextScaler.linear(1.4)),
            child: child!),
        home: Scaffold(
            body: MessagesPage(
                gateway: gateway,
                groups: gateway,
                onRole: (_) async {},
                onGroup: (_) async {},
                onCreate: () {},
                onPartners: () {}))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('创建群聊'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('暖暖'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    gateway.close();
  });
}
