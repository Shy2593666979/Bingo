import 'dart:io';
import 'dart:ui' as ui;
import 'package:bingo/core/design/bingo_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brand foreground decodes with transparency and visible artwork',
      () async {
    final bytes =
        await File('assets/images/bingo_logo_foreground.webp').readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, image.height);
    final pixels = (await image.toByteData())!.buffer.asUint8List();
    expect(pixels[3], 0);
    expect(
        [for (var i = 3; i < pixels.length; i += 4) pixels[i]]
            .any((a) => a > 200),
        isTrue);
    image.dispose();
    codec.dispose();
  });
  for (final size in [45.0, 76.0, 174.0]) {
    testWidgets('shared logo fits branding slot at size $size', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Center(child: BingoWordmark(width: size, height: size))));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(BingoWordmark)), Size.square(size));
      expect(tester.takeException(), isNull);
    });
  }
}
