import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('avatar tones vary across names and stay stable between renders', () {
    final names = ['小夏', '周小雨', '林间风', '奶油吐司', '一颗柠檬', 'Bingo', '阿宁', '木槿'];
    final colors =
        names.map((name) => UserAvatar.toneFor(name).background).toSet();
    expect(colors.length, greaterThanOrEqualTo(3));
    expect(UserAvatar.toneFor('  小夏  '), UserAvatar.toneFor('小夏'));
    for (final name in names) {
      expect(UserAvatar.tones, contains(UserAvatar.toneFor(name)));
    }
  });
  testWidgets('missing and invalid uploads use the last nickname character',
      (tester) async {
    for (final data in [null, '', 'not-base64', 'YWJj']) {
      await tester.pumpWidget(MaterialApp(
          home: UserAvatar(avatarData: data, username: '周小雨', size: 38)));
      await tester.pumpAndSettle();
      expect(find.byType(ClipOval), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('雨'), findsOneWidget);
      expect(tester.widget<Text>(find.text('雨')).style!.color,
          UserAvatar.toneFor('周小雨').foreground);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'empty nickname has a blank avatar and unicode names use complete graphemes',
      (tester) async {
    for (final entry in {
      '': '',
      '  ': '',
      '  小夏  ': '夏',
      'Bingo': 'o',
      '小👨‍👩‍👧‍👦': '👨‍👩‍👧‍👦',
      'Cafe\u0301': 'e\u0301'
    }.entries) {
      expect(UserAvatar.initialFor(entry.key), entry.value);
      await tester.pumpWidget(
          MaterialApp(home: UserAvatar(username: entry.key, size: 38)));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      if (entry.value.isEmpty) {
        expect(find.byType(Text), findsNothing);
      } else {
        expect(find.text(entry.value), findsOneWidget);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('uploaded avatars use the same soft square as default avatars',
      (tester) async {
    const imageData =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jDVsAAAAASUVORK5CYII=';
    await tester.pumpWidget(const MaterialApp(
        home: UserAvatar(
            avatarData: imageData,
            username: '小夏',
            size: 38,
            foregroundColor: Colors.white,
            backgroundGradient:
                LinearGradient(colors: [Colors.green, Colors.teal]))));
    await tester.pumpAndSettle();
    expect(find.byType(ClipOval), findsNothing);
    expect(find.byType(ClipRSuperellipse), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(find.text('夏'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
