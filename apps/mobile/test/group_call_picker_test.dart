import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/group_chat/presentation/group_call_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'call selection requires at least one and excludes inactive members',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final group = ChatGroup.fromJson({
      'id': 'group',
      'name': '测试群',
      'cover': 'coffee',
      'last_activity_at': '2026-11-02T00:00:00Z',
      'members': [
        for (var i = 0; i < 3; i++)
          {
            'id': 'role-$i',
            'name': '搭子$i',
            'role_name': '朋友',
            'active': i < 2,
          }
      ],
    });
    List<GroupPerson>? selected;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      selected = await Navigator.push<List<GroupPerson>>(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  GroupCallPickerPage(group: group)));
                    },
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.text('搭子2'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('发起通话（2）'), findsOneWidget);
    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.text('搭子1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发起通话（1）'));
    await tester.pumpAndSettle();
    expect(selected!.single.id, 'role-1');
    expect(tester.takeException(), isNull);
  });
}
