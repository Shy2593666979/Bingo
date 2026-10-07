import 'package:bingo/features/chat/presentation/widgets/chat_menu_icon.dart';
import 'package:bingo/features/chat/presentation/widgets/companion_moment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in {
    '一起专注': ChatMenuSymbol.focus,
    '小约定': ChatMenuSymbol.promise,
    '陪我入睡': ChatMenuSymbol.sleep,
    '今日小记': ChatMenuSymbol.diary,
  }.entries) {
    testWidgets('${entry.key} chat card uses the same menu vector',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: CompanionMomentCard(content: '[${entry.key}] 测试记录')),
      ));
      final icon = tester.widget<ChatMenuIcon>(find.byType(ChatMenuIcon));
      expect(icon.symbol, entry.value);
      expect(find.byType(Icon), findsNothing);
    });
  }
  for (final symbol in ChatMenuSymbol.values) {
    testWidgets('${symbol.name} renders the HTML vector without a font icon',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(child: ChatMenuIcon(symbol: symbol)),
      ));
      expect(find.byType(Icon), findsNothing);
      final drawing = tester.widget<CustomPaint>(find.byType(CustomPaint).last);
      expect(drawing.size, const Size.square(22));
      expect(tester.takeException(), isNull);
    });
  }
}
