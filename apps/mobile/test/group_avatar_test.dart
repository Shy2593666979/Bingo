import 'dart:io';
import 'dart:ui' as ui;
import 'package:bingo/shared/widgets/group_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const names = ['女朋友', '男朋友', '同事', '老师', '邻家大叔', '弟弟', '闺蜜', '好兄弟', '运动搭子'];
void main() {
  const expectedRows = [
    [1],
    [2],
    [1, 2],
    [2, 2],
    [2, 3],
    [3, 3],
    [1, 3, 3],
    [2, 3, 3],
    [3, 3, 3]
  ];
  for (final size in [44.0, 48.0, 100.0]) {
    for (var count = 1; count <= 9; count++) {
      testWidgets('$count members follow the reference at size $size',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
            home: Center(
                child: GroupAvatar.roles(names.take(count).toList(),
                    size: size))));
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byType(GroupAvatar));
        final cells = [
          for (var i = 0; i < count; i++)
            tester.getRect(find.byKey(ValueKey('group-avatar-tile-$i')))
        ];
        final rows = <double, List<Rect>>{};
        for (final cell in cells) {
          expect(bounds.contains(cell.topLeft), isTrue);
          expect(bounds.contains(cell.bottomRight), isTrue);
          rows.putIfAbsent(cell.top, () => []).add(cell);
        }
        expect(
            rows.values.map((r) => r.length).toList(), expectedRows[count - 1]);
        for (final row in rows.values) {
          expect((row.first.left + row.last.right) / 2,
              closeTo(bounds.center.dx, .001));
        }
        expect((cells.first.top + cells.last.bottom) / 2,
            closeTo(bounds.center.dy, .001));
        for (var i = 0; i < cells.length; i++) {
          for (var j = i + 1; j < cells.length; j++) {
            expect(cells[i].overlaps(cells[j]), isFalse);
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('actual group contains only active AI companions',
      (tester) async {
    final people = [
      for (var i = 0; i < 9; i++)
        GroupPerson.fromJson({
          'id': '$i',
          'name': '搭子$i',
          'role_name': names[i],
          'active': i < 8,
        })
    ];
    await tester.pumpWidget(
        MaterialApp(home: Center(child: GroupAvatar(members: people))));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantAvatar), findsNWidgets(8));
    expect(find.byType(UserAvatar), findsNothing);
    expect(find.byKey(const ValueKey('group-avatar-tile-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-avatar-tile-8')), findsNothing);
    expect(find.byKey(const ValueKey('group-avatar-tile-9')), findsNothing);
  });
  testWidgets('render the complete member layout comparison', (tester) async {
    final output = Platform.environment['BINGO_AVATAR_PREVIEW'];
    if (output == null) return;
    await tester.runAsync(() async {
      final font = FontLoader('BingoSans');
      font.addFont(
          rootBundle.load('assets/fonts/PingFangSanShengTi.ttf'));
      await font.load();
    });
    RoleAvatarStore.assets.clear();
    await tester.binding.setSurfaceSize(const Size(690, 810));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'BingoSans'),
        home: RepaintBoundary(
            key: key,
            child: Scaffold(
                backgroundColor: const Color(0xFFF5F8F7),
                body: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(children: [
                      const Text('群聊头像 · 1–9 人排版',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 20),
                      Expanded(
                          child: GridView.count(
                              crossAxisCount: 3,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: .96,
                              children: [
                            for (var count = 1; count <= 9; count++)
                              Container(
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16)),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        GroupAvatar.roles(
                                            names.take(count).toList(),
                                            size: 110),
                                        const SizedBox(height: 14),
                                        Text(
                                            '$count 人 · ${expectedRows[count - 1].join(' + ')}'),
                                      ]))
                          ])),
                    ]))))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final name in names) {
        await precacheImage(
            AssetImage(squareAvatarAsset(assistantAvatarAsset(name))),
            key.currentContext!);
      }
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(output).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  });
}
