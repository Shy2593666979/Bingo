import 'dart:convert';
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/core/appearance/appearance_page.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final disk = <String, String>{};
  bool failSave = false;
  setUp(() {
    disk.clear();
    failSave = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppearanceStore.channel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final user = args['user_id'] as String;
      if (call.method == 'load') return disk[user];
      if (call.method == 'importPhoto') {
        return '/appearance-test-background.png';
      }
      if (call.method == 'save') {
        if (failSave) throw PlatformException(code: 'disk_full');
        disk[user] = args['data'] as String;
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(AppearanceStore.channel, null));

  test('global inheritance, role override, restart and account isolation',
      () async {
    final store = AppearanceStore('alice');
    await store.load();
    await store.save(const ChatAppearance(background: 'peach', bubble: 'rose'));
    await store.save(const ChatAppearance(background: 'paper', bubble: 'comic'),
        roleId: 'partner-1');
    final restored = AppearanceStore('alice');
    await restored.load();
    expect(restored.effective('partner-1').bubble, 'comic');
    expect(restored.effective('partner-2').bubble, 'rose');
    final other = AppearanceStore('bob');
    await other.load();
    expect(other.effective().bubble, 'mint');
    await restored.save(null, roleId: 'partner-1');
    expect(restored.hasOverride('partner-1'), isFalse);
    expect(restored.effective('partner-1').background, 'peach');
    await restored.save(null);
    expect(restored.effective('partner-1').background, 'mint');
  });

  test('failed persistence preserves the applied appearance', () async {
    final store = AppearanceStore('alice');
    await store.save(const ChatAppearance(bubble: 'ocean'));
    failSave = true;
    await expectLater(store.save(const ChatAppearance(bubble: 'comic')),
        throwsA(isA<PlatformException>()));
    expect(store.effective().bubble, 'ocean');
    expect(jsonDecode(disk['alice']!)['global']['bubble'], 'ocean');
  });

  testWidgets(
      'all skins render long messages, call records and typing at narrow width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final skin in ChatSkin.all) {
      await tester.pumpWidget(MaterialApp(
          home: AppearanceScope(
              value: ChatAppearance(background: skin.id, bubble: skin.id),
              child: Scaffold(
                  body: ChatWallpaper(
                      value: ChatAppearance(background: skin.id),
                      child: ListView(children: [
                        const MessageBubble(
                            message: ChatMessage(
                                id: 'a',
                                role: ChatRole.assistant,
                                content:
                                    '这是一段比较长的文字，用来确认气泡换肤后仍然自然换行，并且保留清晰的阅读体验。'),
                            assistantRole: null),
                        const MessageBubble(
                            message: ChatMessage(
                                id: 'u', role: ChatRole.user, content: '嗯'),
                            assistantRole: null),
                        const CallRecordTile(
                            message: ChatMessage(
                                id: 'c',
                                role: ChatRole.user,
                                content: '',
                                type: ChatMessageType.call,
                                callDurationSeconds: 75)),
                        const AssistantTypingBubble(assistantRole: null),
                      ]))))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: skin.id);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('preview changes stay as drafts until save', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppearanceStore('alice');
    await store.load();
    await tester.pumpWidget(MaterialApp(home: AppearancePage(store: store)));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('appearance-skin-h2_bear')), 240,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('appearance-catalog-2')),
            matching: find.byType(Scrollable)));
    await tester.ensureVisible(find.text('软糖小熊'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('软糖小熊'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AppearanceScope>(find.byType(AppearanceScope).first)
            .value
            .bubble,
        'h2_bear');
    expect(store.effective().bubble, 'mint');
    expect(disk, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bubble catalogue exposes every style in the requested order',
      (tester) async {
    final store = AppearanceStore('catalogue');
    await tester.pumpWidget(MaterialApp(home: AppearancePage(store: store)));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('查看全部气泡款式'), findsNothing);
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate = grid.delegate as SliverChildBuilderDelegate;
    final expected = [
      ...ChatSkin.references,
      ...ChatSkin.h2,
      ...ChatSkin.originals
    ];
    expect(delegate.childCount, expected.length);
    final context = tester.element(find.byType(SliverGrid));
    for (var index = 0; index < expected.length; index++) {
      expect(delegate.builder(context, index)!.key,
          ValueKey('appearance-skin-${expected[index].id}'));
    }
    final scrollable = find.descendant(
        of: find.byKey(const ValueKey('appearance-catalog-2')),
        matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(
        find.byKey(ValueKey('appearance-skin-${ChatSkin.originals.last.id}')),
        250,
        scrollable: scrollable);
    await tester.ensureVisible(find.text(ChatSkin.originals.last.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ChatSkin.originals.last.name));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AppearanceScope>(find.byType(AppearanceScope).first)
            .value
            .bubble,
        ChatSkin.originals.last.id);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('picking a photo resets fade to zero and saves that setting',
      (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/device_tools'),
        (_) async => {
              'bytes': Uint8List.fromList([1, 2, 3])
            });
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/device_tools'), null));
    final store = AppearanceStore('photo');
    await store.save(const ChatAppearance(fade: .6, zoom: 1.7));
    await tester.pumpWidget(
        MaterialApp(home: AppearancePage(store: store, initialTab: 1)));
    await tester.scrollUntilVisible(find.text('从相册选择背景'), 200,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('appearance-catalog-1')),
            matching: find.byType(Scrollable)));
    await tester.tap(find.text('从相册选择背景'));
    await tester.pump();
    final draft = tester
        .widget<AppearanceScope>(find.byType(AppearanceScope).first)
        .value;
    expect(draft.background, 'photo');
    expect(draft.fade, 0);
    expect(draft.zoom, 1);
    await tester.tap(find.text('保存为默认外观'));
    await tester.pumpAndSettle();
    final restored = AppearanceStore('photo');
    await restored.load();
    expect(restored.effective().fade, 0);
    expect(restored.effective().background, 'photo');
    expect(ChatAppearance.fromJson({'background': 'photo'}).fade, 0);
    expect(
        ChatAppearance.fromJson({'background': 'photo', 'fade': .4}).fade, .4);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('every decorated preview fits a narrow screen with larger text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppearanceStore('preview');
    for (final skin in ChatSkin.all) {
      await store.save(ChatAppearance(background: skin.id, bubble: skin.id));
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!),
          home: AppearancePage(key: ValueKey(skin.id), store: store)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: skin.id);
    }
  });
}
