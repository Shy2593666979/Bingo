import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('default and invalid avatars keep the square app logo',
      (tester) async {
    for (final data in [null, '', 'not-base64', 'YWJj']) {
      await tester.pumpWidget(
          MaterialApp(home: UserAvatar(avatarData: data, size: 38)));
      await tester.pumpAndSettle();
      expect(find.byType(ClipOval), findsNothing);
      final image = tester.widget<Image>(find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is AssetImage));
      expect(image.image, isA<AssetImage>());
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('uploaded avatars retain their circular crop', (tester) async {
    const imageData =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jDVsAAAAASUVORK5CYII=';
    await tester.pumpWidget(
        const MaterialApp(home: UserAvatar(avatarData: imageData, size: 38)));
    await tester.pumpAndSettle();
    expect(find.byType(ClipOval), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(tester.takeException(), isNull);
  });
}
