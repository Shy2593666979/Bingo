import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('companion primary actions share option B colors and shape', () {
    for (final height in [54.0, 56.0]) {
      final style = companionActionButtonStyle(height: height);
      expect(style.backgroundColor!.resolve({}), const Color(0xFFBFE5D4));
      expect(style.foregroundColor!.resolve({}), const Color(0xFF275C48));
      expect(
          style.side!.resolve({}), const BorderSide(color: Color(0xFFB0D7C5)));
      expect(style.shape!.resolve({}), isA<StadiumBorder>());
      expect(style.minimumSize!.resolve({}), Size(0, height));
      expect(style.backgroundColor!.resolve({WidgetState.disabled}), isNull);
    }
  });

  test('system font theme preserves the existing palette and text sizes', () {
    final theme = buildBingoTheme();
    final baseline = ThemeData(
      colorScheme: theme.colorScheme,
      useMaterial3: true,
    );

    expect(theme.textTheme.bodyMedium?.fontFamily,
        baseline.textTheme.bodyMedium?.fontFamily);
    expect(theme.textTheme.titleLarge?.fontFamily,
        baseline.textTheme.titleLarge?.fontFamily);
    expect(theme.primaryTextTheme.bodyMedium?.fontFamily,
        baseline.primaryTextTheme.bodyMedium?.fontFamily);
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
    final expectedFamily =
        ThemeData(useMaterial3: true).textTheme.bodyMedium?.fontFamily;
    expect(text.text.style?.fontFamily, expectedFamily);
    expect(mint.textTheme.bodyMedium?.fontFamily, expectedFamily);
    expect(mint.colorScheme.primary, BingoPalette.mintPrimary);
  });
}
