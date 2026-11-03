import 'package:bingo/features/group_chat/presentation/widgets/chat_quote_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final isUser in [false, true]) {
    testWidgets('quote retains source text without an accent, user=$isUser',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 230,
                      child: ChatQuoteCard(
                          sender: '星星',
                          content: '今晚早点休息。\n明天我们再接着聊。',
                          createdAt: DateTime.utc(2026, 11, 1, 15, 31),
                          isUser: isUser))))));
      final accent = find.byKey(const ValueKey('chat-quote-accent'));
      expect(accent, findsNothing);
      expect(find.text('星星'), findsOneWidget);
      expect(find.text('23:31'), findsOneWidget);
      expect(find.text('今晚早点休息。\n明天我们再接着聊。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
