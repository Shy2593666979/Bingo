import 'dart:ui' as ui;
import 'package:bingo/core/design/approved_art.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation keeps home height across tabs and the create page',
      (tester) async {
    for (final scale in [1.0, 1.4, 2.0]) {
      double? homeHeight;
      for (final selected in [0, 1, 2, 3, 4]) {
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(bottom: 24),
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                bottomNavigationBar: ReferenceNavigation(
                    selected: selected == 4 ? 0 : selected,
                    homeStyle: selected == 0,
                    creating: selected == 4,
                    onSelected: (_) {},
                    onCreate: () {}))));
        final height = tester.getSize(find.byType(ReferenceNavigation)).height;
        homeHeight ??= height;
        expect(height, homeHeight, reason: 'tab $selected, text scale $scale');
        expect(height, closeTo(64 + (13 * scale - 13) * 1.4 + 24, .01));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('home states have identical outer bounds and door opening',
      (tester) async {
    List<int>? bounds;
    for (final page in [0, 1]) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: RepaintBoundary(
                  key: key, child: ApprovedNavIcon(page: page, item: 0)))));
      final pixels = await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      var left = 52, top = 52, right = 0, bottom = 0;
      for (var y = 0; y < 52; y++) {
        for (var x = 0; x < 52; x++) {
          if (pixels![(y * 52 + x) * 4 + 3] < 128) continue;
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
      final actual = [left, top, right, bottom];
      bounds ??= actual;
      expect(actual, bounds);
      expect(pixels![(44 * 52 + 26) * 4 + 3], 0);
    }
  });
  testWidgets('inactive destination glyphs stay identical on every page',
      (tester) async {
    for (final item in [0, 1, 3, 4]) {
      List<int>? expected;
      for (final page in [0, 1, 2, 3, 4].where((page) => page != item)) {
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
            home: Center(
                child: RepaintBoundary(
                    key: key,
                    child: ApprovedNavIcon(page: page, item: item)))));
        await tester.pump();
        final bytes = await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final data =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          return data!.buffer.asUint8List().toList();
        });
        expected ??= bytes;
        expect(bytes, orderedEquals(expected!),
            reason: 'item $item on page $page');
      }
    }
  });
}
