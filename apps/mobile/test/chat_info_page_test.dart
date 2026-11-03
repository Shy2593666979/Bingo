import 'dart:async';

import 'package:bingo/core/appearance/appearance_page.dart';
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_info_page.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/roles/data/local_role_order_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements ChatGateway, ConversationGateway, ChatInfoGateway {
  ChatSettings settings = const ChatSettings();
  bool failSave = false, cleared = false;
  List<ChatMessage> history = [
    const ChatMessage(id: 'one', role: ChatRole.user, content: '今天有点累')
  ];
  final searches = <String, Completer<List<ChatMessage>>>{};
  @override
  Future<List<ChatMessage>> listMessages(String id) async => history;
  @override
  Future<ChatSettings> getChatSettings(String id) async => settings;
  @override
  Future<ChatSettings> updateChatSettings(String id,
      {bool? muted, bool? pinned}) async {
    if (failSave) throw StateError('offline');
    return settings = ChatSettings(
        muted: muted ?? settings.muted, pinned: pinned ?? settings.pinned);
  }

  @override
  Future<void> clearChatMessages(String id) async {
    cleared = true;
    history = [];
  }

  @override
  Future<List<ChatMessage>> searchChatMessages(String id, String query) =>
      (searches[query] = Completer<List<ChatMessage>>()).future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('pinning partitions local order and preserves each group order', () {
    const roles = [
      RoleOption(id: 'a', name: 'a', builtin: true),
      RoleOption(id: 'b', name: 'b', builtin: true, pinned: true),
      RoleOption(id: 'c', name: 'c', builtin: true, pinned: true)
    ];
    expect(applyLocalRoleOrder(roles, ['c', 'a', 'b']).map((role) => role.id),
        ['c', 'b', 'a']);
  });

  Future<(_Gateway, ChatController)> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _Gateway();
    final controller = ChatController(gateway: gateway, remoteHistory: gateway);
    await controller.bindConversation('alice', 'first', '女朋友');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ChatInfoPage(
            controller: controller,
            gateway: gateway,
            partnerName: '甜甜',
            partnerRole: '女朋友',
            appearanceStore: AppearanceStore('alice'),
            roleId: 'girlfriend')));
    await tester.pumpAndSettle();
    return (gateway, controller);
  }

  testWidgets(
      'settings failure keeps old switch and clear requires confirmation',
      (tester) async {
    final (gateway, controller) = await open(tester);
    gateway.failSave = true;
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first)
            .value,
        false);
    gateway.failSave = false;
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pumpAndSettle();
    expect(gateway.settings.muted, true);
    await tester.ensureVisible(find.text('清空聊天记录'));
    await tester.tap(find.text('清空聊天记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(gateway.cleared, false);
    expect(controller.messages, isNotEmpty);
    await tester.tap(find.text('清空聊天记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(gateway.cleared, true);
    expect(controller.messages, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search ignores stale responses and background opens correct tab',
      (tester) async {
    final (gateway, _) = await open(tester);
    await tester.tap(find.text('查找聊天记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '旧词');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), '新词');
    await tester.pump(const Duration(milliseconds: 350));
    gateway.searches['新词']!.complete(
        [const ChatMessage(id: 'new', role: ChatRole.user, content: '新词结果')]);
    await tester.pumpAndSettle();
    gateway.searches['旧词']!.complete(
        [const ChatMessage(id: 'old', role: ChatRole.user, content: '旧词结果')]);
    await tester.pumpAndSettle();
    expect(find.text('新词结果'), findsOneWidget);
    expect(find.text('旧词结果'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天外观'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<AppearancePage>(find.byType(AppearancePage)).initialTab,
        2);
    expect(tester.takeException(), isNull);
  });
}
