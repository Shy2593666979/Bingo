import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(RoleAvatarStore.clear);
  testWidgets('new built-in portraits resolve by relation and by server asset',
      (tester) async {
    const additions = {
      '邻家大叔': 'parent',
      '弟弟': 'child',
      '闺蜜': 'bestie',
      '好兄弟': 'bro',
      '学姐': 'senior_sister',
      '学长': 'senior_brother',
      '树洞搭子': 'confidant',
      '运动搭子': 'fitness',
      '董事长': 'chairman',
      '公司高管': 'executive',
      '网红人物': 'xiaofan',
    };
    for (final entry in additions.entries) {
      final role = RoleOption.fromJson({
        'id': entry.value,
        'name': entry.key,
        'nickname': '新搭子',
        'builtin': true,
        'avatar_asset': '${entry.value}.png'
      });
      expect(squareAvatarAsset(role.avatarAsset!),
          'assets/avatars_square/${entry.value}.webp');
    }
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Wrap(children: [
      for (final relation in additions.keys)
        AssistantAvatar(role: relation, size: 48)
    ]))));
    await tester.pumpAndSettle();
    for (final code in additions.values) {
      expect(
          find.byWidgetPredicate((w) =>
              w is Image &&
              ((w.image is ResizeImage
                          ? (w.image as ResizeImage).imageProvider
                          : w.image) as AssetImage)
                      .assetName ==
                  'assets/avatars_square/$code.webp'),
          findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
