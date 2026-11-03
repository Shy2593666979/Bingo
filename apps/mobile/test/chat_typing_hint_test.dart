import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
import 'package:bingo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chat_controller_test.dart' as f;

void main() {
  testWidgets('A hint follows messages through every bubble wait',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('bingo/device_tools'), (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('bingo/device_tools'), null));
    final gateway = f.InterruptibleChatGateway();
    final controller = ChatController(gateway: gateway);
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            controller: controller,
            assistantName: '甜甜',
            assistantRole: '女朋友',
            speechGateway: f.FakeSpeechGateway(),
            onStartCall: () {},
            onIncomingCall: (_) async {},
            onOpenSettings: () {})));
    await tester.pumpAndSettle();
    final sending = controller.send('今天有点累');
    await tester.pump();
    await tester.pump();
    expect(controller.isWaitingForReply, isTrue);
    final hint = find.byKey(const ValueKey('chat-typing-hint'));
    expect(hint, findsOneWidget);
    expect(tester.getRect(hint).bottom,
        lessThan(tester.getRect(find.byType(MessageInput)).top));
    expect(find.ancestor(of: hint, matching: find.byType(ListView)),
        findsOneWidget);
    expect(find.byType(MessageBubble), findsOneWidget);
    final stream = gateway.streams.values.single;
    stream.add(const ChatStarted('conversation'));
    stream.add(const ChatSegment('那就慢慢说，我在听。'));
    await tester.pump();
    await tester.pump();
    expect(controller.isWaitingForReply, isTrue);
    expect(hint, findsOneWidget);
    // The first reply must not suppress the hint while the next is generated.
    await tester.pump(const Duration(milliseconds: 100));
    expect(hint, findsOneWidget);
    stream.add(const ChatSegment('休息一会儿也没关系。'));
    stream.add(ChatFinished('reply', createdAt: DateTime.utc(2026, 11, 2, 12)));
    await stream.close();
    await tester.pump();
    await tester.pump();
    // Even a completed response can still have a hidden, paced second bubble.
    expect(controller.messages, hasLength(2));
    expect(controller.isWaitingForReply, isTrue);
    expect(hint, findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await sending;
    await tester.pumpAndSettle();
    expect(controller.messages, hasLength(3));
    expect(controller.isWaitingForReply, isFalse);
    expect(hint, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });
}
