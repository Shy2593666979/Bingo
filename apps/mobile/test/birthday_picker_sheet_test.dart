import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/shared/widgets/birthday_picker_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openPicker(WidgetTester tester, DateTime initial,
      ValueChanged<DateTime?> onPicked) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async => onPicked(await showBirthdayPicker(
                        context,
                        initialDate: initial)),
                    child: const Text('生日'))))));
    await tester.tap(find.text('生日'));
    await tester.pumpAndSettle();
  }

  testWidgets('month changes clamp the day to a valid date', (tester) async {
    DateTime? result;
    await openPicker(tester, DateTime(2023, 1, 31), (date) => result = date);
    final month =
        tester.widget<CupertinoPicker>(find.byType(CupertinoPicker).at(1));
    month.scrollController!.jumpToItem(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2023, 2, 28));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing leap year clamps February 29', (tester) async {
    DateTime? result;
    await openPicker(tester, DateTime(2024, 2, 29), (date) => result = date);
    final year =
        tester.widget<CupertinoPicker>(find.byType(CupertinoPicker).first);
    year.scrollController!.jumpToItem(2023 - 1900);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2023, 2, 28));
    expect(tester.takeException(), isNull);
  });

  testWidgets('future dates are limited to today', (tester) async {
    DateTime? result;
    final today = DateUtils.dateOnly(DateTime.now());
    await openPicker(
        tester, today.add(const Duration(days: 365)), (date) => result = date);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, today);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel does not return a birthday', (tester) async {
    DateTime? result = DateTime(2000);
    await openPicker(tester, DateTime(2000), (date) => result = date);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
