import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/shared/widgets/partner_swipe_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty role identities never leave a separator on cards', () {
    const blank = RoleOption(
        id: 'custom',
        name: '晚晚',
        builtin: false,
        roleType: '',
        description: '耐心陪你聊聊');
    const typed = RoleOption(
        id: 'custom',
        name: '晚晚',
        builtin: false,
        roleType: '朋友',
        description: '耐心陪你聊聊');
    const noDescription =
        RoleOption(id: 'custom', name: '晚晚', builtin: false, roleType: '朋友');
    expect(blank.cardDescription, '耐心陪你聊聊');
    expect(typed.cardDescription, '朋友 · 耐心陪你聊聊');
    expect(noDescription.cardDescription, '朋友');
  });

  for (final builtin in [true, false]) {
    testWidgets(
        'swiping ${builtin ? 'built-in' : 'private'} partner exposes allowed actions',
        (tester) async {
      var edited = false;
      var deleted = false;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 340,
                      child: PartnerSwipeCard(
                          onEdit: () => edited = true,
                          onDelete: builtin ? null : () => deleted = true,
                          child: const Material(
                              color: Colors.white,
                              child: SizedBox(
                                  height: 130,
                                  child: Center(child: Text('伙伴'))))))))));
      expect(find.text('编辑'), findsNothing);
      await tester.drag(find.text('伙伴'), const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除'), builtin ? findsNothing : findsOneWidget);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(edited, isTrue);
      expect(deleted, isFalse);
      if (!builtin) {
        await tester.drag(find.text('伙伴'), const Offset(-160, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        expect(deleted, isTrue);
      }
      await tester.drag(find.text('伙伴'), const Offset(-160, 0));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('编辑'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
