import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('companion actions share the mint surface and existing shape', () {
    for (final height in [54.0, 56.0]) {
      final style = companionActionButtonStyle(height: height);
      expect(style.backgroundColor!.resolve({}),
          BingoPalette.companionActionSurface);
      expect(
          style.foregroundColor!.resolve({}), BingoPalette.companionActionInk);
      expect(style.side!.resolve({}),
          const BorderSide(color: BingoPalette.companionActionBorder));
      expect(style.shape!.resolve({}), isA<StadiumBorder>());
      expect(style.minimumSize!.resolve({}), Size(0, height));
      expect(style.backgroundColor!.resolve({WidgetState.disabled}), isNull);
    }
  });

  test('mint action and supporting text remain readable on their surfaces', () {
    double contrast(Color a, Color b) {
      final one = a.computeLuminance(), two = b.computeLuminance();
      return ((one > two ? one : two) + .05) / ((one < two ? one : two) + .05);
    }

    expect(
        contrast(Colors.white, BingoPalette.primary), greaterThanOrEqualTo(3));
    expect(contrast(Colors.white, BingoPalette.primaryText),
        greaterThanOrEqualTo(4.5));
    expect(contrast(BingoPalette.muted, BingoPalette.surface),
        greaterThanOrEqualTo(4.5));
    expect(
        contrast(BingoPalette.ink, BingoPalette.ice), greaterThanOrEqualTo(7));
  });

  test('system font theme preserves the existing palette and text sizes', () {
    final theme = buildBingoTheme();
    final baseline = ThemeData(
      colorScheme: theme.colorScheme,
      useMaterial3: true,
    );

    expect(theme.textTheme.bodyMedium?.fontFamily, 'BingoSans');
    expect(theme.textTheme.titleLarge?.fontFamily, 'BingoSans');
    expect(theme.primaryTextTheme.bodyMedium?.fontFamily, 'BingoSans');
    expect(theme.textTheme.bodyMedium?.fontSize,
        baseline.textTheme.bodyMedium?.fontSize);
    expect(theme.colorScheme.primary, BingoPalette.blue);
    expect(theme.scaffoldBackgroundColor, BingoPalette.ice);
  });

  testWidgets('mint pages and plain text inherit the system font',
      (tester) async {
    late ThemeData mint;

    await tester.pumpWidget(MaterialApp(
      theme: buildBingoTheme(),
      home: Builder(builder: (context) {
        mint = buildMintTheme(context);
        return Theme(
          data: mint,
          child: const Scaffold(
            body: Text('今天想聊点什么？', style: TextStyle(fontSize: 16)),
          ),
        );
      }),
    ));

    final text = tester.widget<RichText>(find.byType(RichText).first);
    const expectedFamily = 'BingoSans';
    expect(text.text.style?.fontFamily, expectedFamily);
    expect(mint.textTheme.bodyMedium?.fontFamily, expectedFamily);
    expect(mint.colorScheme.primary, BingoPalette.mintPrimary);
  });
}
