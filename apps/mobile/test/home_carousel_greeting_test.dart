import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/roles/presentation/home_companion_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'prepared greetings stay unchanged across forward and reverse drags',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(14),
                child: HomeCompanionCarousel(
                    roles: const [
                      RoleOption(
                          id: 'a', name: '女朋友', nickname: '甜甜', builtin: true),
                      RoleOption(
                          id: 'b', name: '老师', nickname: '小田老师', builtin: true),
                      RoleOption(
                          id: 'c', name: '邻家大叔', nickname: '陈叔', builtin: true),
                    ],
                    active: true,
                    onChat: (_) async {},
                    onDetail: (_) async {},
                    onAll: () {})))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('上一位搭子'), findsNothing);
    expect(find.byTooltip('下一位搭子'), findsNothing);
    String text(String id) => tester
        .widget<Text>(find.byKey(ValueKey('carousel-greeting-$id')))
        .data!;
    Future<void> drag(String target, double direction) async {
      final pager = find.byType(PageView);
      final width = tester.getSize(pager).width;
      final gesture = await tester.startGesture(tester.getCenter(pager));
      await gesture.moveBy(Offset(direction * width * .25, 0));
      await tester.pump(const Duration(milliseconds: 40));
      final prepared = text(target);
      await gesture.moveBy(Offset(direction * width * .4, 0));
      await tester.pump(const Duration(milliseconds: 40));
      expect(text(target), prepared,
          reason: 'onPageChanged must not replace an entering greeting');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(text(target), prepared,
          reason: 'settling must not change the visible greeting');
    }

    await drag('b', -1);
    await drag('a', 1);
    await drag('c', 1);
    await drag('a', -1);
    final outgoing = text('a');
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 60));
    final incoming = text('b');
    expect(text('a'), outgoing);
    await tester.pumpAndSettle();
    expect(text('b'), incoming);
    await tester.tap(find.byKey(const ValueKey('carousel-dot-c')));
    await tester.pumpAndSettle();
    expect(find.text('和陈叔聊聊').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
