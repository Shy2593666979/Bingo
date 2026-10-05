import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
