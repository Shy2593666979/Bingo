import 'dart:io';
import 'dart:ui' as ui;
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final skins = [...ChatSkin.references, ...ChatSkin.h2];
  testWidgets('decorative short messages fit content and long messages grow',
      (tester) async {
    for (final skin in skins) {
      Future<void> show(String text) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: 260,
                      child: Align(
                          alignment: Alignment.topLeft,
                          child: SkinBubbleFrame(
                              key: const ValueKey('bubble'),
                              skin: skin,
                              isUser: false,
                              child: Text(text,
                                  style: const TextStyle(
                                      fontSize: 15, height: 1.45)))))))));
      await show('晚安啦');
      final short = tester.getSize(find.byKey(const ValueKey('bubble')));
      expect(short.width, lessThan(140), reason: skin.id);
      expect(short.height, lessThan(70), reason: skin.id);
      await show(List.filled(15, '今天也辛苦了，早点休息。').join());
      final long = tester.getSize(find.byKey(const ValueKey('bubble')));
      expect(long.height, greaterThan(short.height), reason: skin.id);
      expect(long.width, lessThanOrEqualTo(260), reason: skin.id);
      expect(tester.takeException(), isNull, reason: skin.id);
    }
  });

  testWidgets(
      'all illustrated assets paint without overflow at large text size',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font = FontLoader('BingoSans')
        ..addFont(
            rootBundle.load('assets/fonts/PingFangSanShengTi.ttf'));
      await font.load();
    });
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'BingoSans'),
        home: Scaffold(
            body: SingleChildScrollView(
                child: RepaintBoundary(
                    key: boundaryKey,
                    child: ColoredBox(
                        color: const Color(0xffeafbf7),
                        child: Wrap(children: [
                          for (final skin in skins)
                            SizedBox(
                                width: 400,
                                height: 340,
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(skin.id),
                                          const SizedBox(height: 8),
                                          SkinBubbleFrame(
                                              skin: skin,
                                              isUser: false,
                                              child: const Text('Good night',
                                                  style: TextStyle(
                                                      fontSize: 15,
                                                      height: 1.45))),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                              width: 276,
                                              child: SkinBubbleFrame(
                                                  skin: skin,
                                                  isUser: true,
                                                  child: const Text(
                                                      'Take a little rest. You have done enough today. I am here for you.',
                                                      textScaler:
                                                          TextScaler.linear(
                                                              1.3),
                                                      style: TextStyle(
                                                          fontSize: 15,
                                                          height: 1.45)))),
                                        ])))
                        ])))))));
    await tester.runAsync(() async {
      final context = tester.element(find.byKey(boundaryKey));
      await Future.wait([
        for (final skin in skins)
          precacheImage(
              AssetImage(skin.asset ?? 'assets/chat_bubbles/h2-atlas.webp'),
              context)
      ]);
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (Platform.environment['WRITE_BUBBLE_PREVIEW'] == '1') {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
            '../../docs/previews/assets/decorative-bubbles/skin-check.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
