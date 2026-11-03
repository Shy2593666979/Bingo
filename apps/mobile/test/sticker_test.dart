import 'dart:convert';
import 'package:bingo/features/stickers/sticker.dart';
import 'package:bingo/features/stickers/sticker_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all captions and sprite cells survive message persistence', () {
    expect(ChatSticker.builtins.length, 24);
    for (final sticker in ChatSticker.builtins) {
      final restored = ChatSticker.parse(sticker.encode())!;
      expect(restored.label, sticker.label);
      expect(restored.asset, sticker.asset);
      expect(restored.index, sticker.index);
      expect(ChatSticker.preview(sticker.encode()), '[表情] ${sticker.label}');
    }
    expect(ChatSticker.builtins.take(4).map((s) => s.label),
        ['喜欢你', '抱抱', '晚安啦', '送你小花']);
    expect(ChatSticker.parse('普通消息'), isNull);
    expect(ChatSticker.parse('${ChatSticker.prefix}bad${ChatSticker.suffix}'),
        isNull);
  });

  test('custom sticker captions persist without losing original Unicode', () {
    const sticker = ChatSticker(
        id: 'custom_12345678-1234-1234-1234-123456789abc',
        label: '晚安啦🌙',
        description: '晚安啦🌙');
    final stored = jsonDecode(jsonEncode({'content': sticker.encode()}));
    expect(ChatSticker.parse(stored['content'])!.label, '晚安啦🌙');
  });

  testWidgets('plain grid starts with plus and sends the captioned sticker',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ChatSticker? sent;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: StickerPanel(onSend: (sticker) => sent = sticker)))));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('添加自己的表情'), findsOneWidget);
    expect(find.text('抱抱'), findsOneWidget);
    expect(find.text('晚安啦'), findsOneWidget);
    expect(find.text('我的表情'), findsNothing);
    expect(find.text('管理'), findsNothing);
    await tester.tap(find.text('晚安啦'));
    expect(sent!.label, '晚安啦');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: StickerMessageView(sent!))));
    await tester.pumpAndSettle();
    expect(find.text('晚安啦'), findsOneWidget);
    expect(find.byType(StickerArt), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
