import 'dart:math' as math;
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/widgets/chat_viewport_resize.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
import 'package:bingo/features/stickers/sticker_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Speech implements SpeechGateway {
  @override
  Future<String> transcribe(Uint8List wavAudio) async => '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = MethodChannel('bingo/device_tools');
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(device, (_) async => null));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(device, null));

  for (final group in [false, true]) {
    for (final trigger in ['表情', '更多功能']) {
      testWidgets(
          '$trigger reserves layout, follows latest and preserves history in group=$group',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final scroll = ScrollController();
        var headerTaps = 0;
        await tester.pumpWidget(MaterialApp(
            theme: buildBingoTheme(),
            home: Scaffold(
              resizeToAvoidBottomInset: false,
              body: Column(children: [
                TextButton(
                    key: const ValueKey('header'),
                    onPressed: () => headerTaps++,
                    child: const Text('聊天标题')),
                Expanded(
                    child: ChatViewportResize(
                        key: const ValueKey('viewport'),
                        controller: scroll,
                        child: ListView.builder(
                            controller: scroll,
                            itemCount: 40,
                            itemExtent: 72,
                            itemBuilder: (_, i) => SizedBox(
                                key: ValueKey('row-$i'),
                                height: 72,
                                child: Center(child: Text('聊天消息 $i')))))),
                MessageInput(
                    enabled: true,
                    onSend: (_) {},
                    onCall: () {},
                    speechGateway: _Speech(),
                    referenceStyle: true,
                    initialVoiceMode: false,
                    groupMenu: group,
                    reserveKeyboardSpace: true),
              ]),
            )));
        await tester.pumpAndSettle();
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final original = tester.getRect(find.byKey(const ValueKey('viewport')));
        await tester.tap(find.byTooltip(trigger));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final intermediateHeight =
            tester.getSize(find.byKey(const ValueKey('viewport'))).height;
        await tester.pumpAndSettle();
        final expanded = tester.getRect(find.byKey(const ValueKey('viewport')));
        expect(expanded.height, lessThan(original.height - 90));
        expect(intermediateHeight, greaterThan(expanded.height));
        expect(intermediateHeight, lessThan(original.height));
        expect(scroll.position.extentAfter, closeTo(0, .1));
        expect(tester.getRect(find.byKey(const ValueKey('row-39'))).bottom,
            lessThanOrEqualTo(expanded.bottom + .1));
        expect(expanded.bottom,
            closeTo(tester.getTopLeft(find.byType(MessageInput)).dy, .1));
        // Outside taps close the panel without consuming the intended action.
        await tester.tap(find.byKey(const ValueKey('header')));
        await tester.pumpAndSettle();
        expect(headerTaps, 1);
        expect(tester.getSize(find.byKey(const ValueKey('viewport'))).height,
            closeTo(original.height, .1));
        // Reading history must stay at the same offset during open and close.
        scroll.jumpTo(300);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(trigger));
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(300, .1));
        final panelHeight = tester
            .getSize(find.byKey(const ValueKey('composer-panel-space')))
            .height;
        // Keyboard and panel share one slot, including IME transition frames.
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        expect(
            tester
                .getSize(find.byKey(const ValueKey('composer-panel-space')))
                .height,
            closeTo(math.max(panelHeight, 280), .1));
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(find.byType(StickerPanel), findsNothing);
        expect(find.text(group ? '照片' : '相册'), findsNothing);
        expect(
            tester
                .getSize(find.byKey(const ValueKey('composer-panel-space')))
                .height,
            closeTo(280, .1));
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(300, .1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      });
    }
  }
}
