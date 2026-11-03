import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:bingo/features/stickers/sticker.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as f;

void main() {
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), (_) async => null));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), null));

  testWidgets(
      'header and message avatars open details and insert a name without sending',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = f.RecoveringChatGateway([
      ChatMessage(
          id: 'answer',
          role: ChatRole.assistant,
          content: '你好呀',
          createdAt: DateTime.utc(2026, 11, 3),
          assistantRole: '女朋友'),
    ]);
    final controller = ChatController(gateway: gateway, remoteHistory: gateway);
    await controller.bindConversation('user', 'conversation', '女朋友');
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            controller: controller,
            assistantName: '甜甜',
            assistantRole: '女朋友',
            speechGateway: f.FakeSpeechGateway(),
            onStartCall: () {},
            onIncomingCall: (_) async {},
            onOpenSettings: () {},
            onOpenRoleDetails: () => opened++)));
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('chat-header-avatar'));
    final avatar = find.byKey(
        ValueKey('chat-message-avatar-${controller.messages.single.id}'));
    await tester.tap(header);
    await tester.tap(avatar);
    expect(opened, 2);
    await tester.enterText(find.byType(TextField), '先留着');
    tester.widget<TextField>(find.byType(TextField)).controller!.selection =
        const TextSelection.collapsed(offset: 1);
    await tester.tap(find.byTooltip('语音输入'));
    await tester.pumpAndSettle();
    expect(find.text('按住说话'), findsOneWidget);
    await tester.longPress(header);
    await tester.pumpAndSettle();
    var input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, '先甜甜 留着');
    expect(input.focusNode!.hasFocus, isTrue);
    expect(find.text('按住说话'), findsNothing);
    await tester.longPress(avatar);
    await tester.pumpAndSettle();
    input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, '先甜甜 甜甜 留着');
    expect(opened, 2);
    expect(controller.messages, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  for (final kind in ['通话', '位置', '表情']) {
    testWidgets('$kind record avatar supports details and name insertion',
        (tester) async {
      final message = ChatMessage(
          id: 'record',
          role: ChatRole.assistant,
          content: kind == '表情' ? ChatSticker.builtins.first.encode() : kind,
          type: kind == '通话' ? ChatMessageType.call : ChatMessageType.chat,
          location: kind == '位置'
              ? const ChatLocation(name: '公园', address: '测试地点')
              : null);
      final gateway = f.RecoveringChatGateway([message]);
      final controller =
          ChatController(gateway: gateway, remoteHistory: gateway);
      await controller.bindConversation('user', 'conversation', '女朋友');
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
          home: ChatPage(
              controller: controller,
              assistantName: '甜甜',
              assistantRole: '女朋友',
              speechGateway: f.FakeSpeechGateway(),
              onStartCall: () {},
              onIncomingCall: (_) async {},
              onOpenSettings: () {},
              onOpenRoleDetails: () => opened++)));
      await tester.pumpAndSettle();
      final avatar = find.byKey(const ValueKey('chat-message-avatar-record'));
      await tester.tap(avatar);
      expect(opened, 1);
      await tester.longPress(avatar);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '甜甜 ');
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}
