import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:bingo/core/design/bingo_wordmark.dart';
import 'package:bingo/core/theme/app_theme.dart';
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
      // Compare geometry independently of the current brand accent hue.
      bool ink(List<int> bytes, int i, int solidMinimum) {
        final minimum =
            math.min(bytes[i], math.min(bytes[i + 1], bytes[i + 2]));
        final coverage = (255 - minimum) / (255 - solidMinimum);
        final ray = bytes[i] > 220 && bytes[i + 1] < 220 && bytes[i + 2] < 170;
        return bytes[i + 3] > 128 && (coverage > .47 || ray);
      }

      final accent = BingoPalette.primary.toARGB32();
      final actualMinimum = math.min(
          (accent >> 16) & 255, math.min((accent >> 8) & 255, accent & 255));
      var intersection = 0, union = 0;
      for (var i = 0; i < a.length; i += 4) {
        // The reference's original solid teal is #09A39B. Normalize edge
        // coverage so recoloring does not move the antialiasing threshold.
        final x = ink(a, i, actualMinimum), y = ink(b, i, 9);
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
