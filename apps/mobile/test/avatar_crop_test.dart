import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:bingo/features/auth/presentation/avatar_crop_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rounded preview exports a full square photo with opaque corners',
      (tester) async {
    late Uint8List source;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const Color(0xFF30A080), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      source = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
    });
    Uint8List? saved;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      saved = await Navigator.of(context).push<Uint8List>(
                          MaterialPageRoute(
                              builder: (_) => AvatarCropPage(image: source)));
                    },
                    child: const Text('选择图片'))))));
    await tester.tap(find.text('选择图片'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byType(ClipRSuperellipse), findsOneWidget);
    expect(find.byType(ClipOval), findsNothing);
    await tester.ensureVisible(find.text('使用这张头像'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final button = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '使用这张头像'));
      await (button.onPressed as dynamic)();
    });
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(saved!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 512);
      expect(frame.image.height, 512);
      final rgba = (await frame.image.toByteData())!.buffer.asUint8List();
      for (final index in [0, 511, 511 * 512, 512 * 512 - 1]) {
        expect(rgba[index * 4 + 3], 255);
      }
      frame.image.dispose();
      codec.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
