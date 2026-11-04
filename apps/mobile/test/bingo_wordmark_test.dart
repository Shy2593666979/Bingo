import 'dart:io';
import 'dart:ui' as ui;
import 'package:bingo/core/design/bingo_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'vector wordmark preserves the approved letter and ray silhouettes',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: RepaintBoundary(
                key: key,
                child: const ColoredBox(
                    color: Colors.white,
                    child: BingoWordmark(width: 93, height: 36))))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    await tester.runAsync(() async {
      final actual = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final codec = await ui.instantiateImageCodec(
          await File('assets/branding/bingo_wordmark_e.png').readAsBytes());
      final reference = (await codec.getNextFrame()).image;
      final a = (await actual.toByteData())!.buffer.asUint8List();
      final b = (await reference.toByteData())!.buffer.asUint8List();
      bool ink(List<int> bytes, int i) =>
          (bytes[i] < 140 && bytes[i + 1] < 220) ||
          (bytes[i] > 220 && bytes[i + 1] < 220 && bytes[i + 2] < 170);
      var intersection = 0, union = 0;
      for (var i = 0; i < a.length; i += 4) {
        final x = ink(a, i), y = ink(b, i);
        if (x && y) intersection++;
        if (x || y) union++;
      }
      expect(intersection / union, greaterThan(.95));
      final preview = Platform.environment['BINGO_WORDMARK_PREVIEW'];
      if (preview != null) {
        final data = await actual.toByteData(format: ui.ImageByteFormat.png);
        await File(preview).writeAsBytes(data!.buffer.asUint8List());
      }
      actual.dispose();
      reference.dispose();
      codec.dispose();
    });
  });
}
