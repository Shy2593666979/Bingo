import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/companion_selection_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const profile = UserProfile(
    id: 'u',
    phone: '123456',
    username: '用户',
    assistantName: '甜甜',
    personality: '温柔体贴',
    role: '女朋友',
    onboardingComplete: true);

class Gateway implements CompanionSelectionGateway {
  final saved = <List<String>>[];
  bool fail = false;
  @override
  Future<List<RoleOption>> companionCandidates() async => const [
        RoleOption(
            id: 'a',
            name: '女朋友',
            nickname: '甜甜',
            builtin: true,
            avatarAsset: 'assets/avatars_square/girlfriend.png'),
        RoleOption(
            id: 'b',
            name: '男朋友',
            nickname: '暖暖',
            builtin: true,
            avatarAsset: 'assets/avatars_square/boyfriend.png'),
      ];
  @override
  Future<UserProfile> selectCompanions(List<String> ids) async {
    saved.add([...ids]);
    if (fail) throw StateError('offline');
    return profile;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final audio = <String>[];
  Uint8List? playedBytes;
  setUp(() {
    audio.clear();
    playedBytes = null;
    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('bingo/device_tools'),
            (call) async {
      audio.add(call.method);
      if (call.method == 'playPreviewAudio') {
        playedBytes = call.arguments as Uint8List;
      }
      return null;
    });
  });

  Future<void> open(WidgetTester tester, Gateway gateway,
      {Future<void> Function(UserProfile)? complete}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: CompanionSelectionPage(
            gateway: gateway, onComplete: complete ?? (_) async {})));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    }
    await tester.pumpAndSettle();
  }

  testWidgets('swiping browses; explicit multi-selection and zero guard',
      (tester) async {
    final gateway = Gateway();
    var completed = false;
    await open(tester, gateway, complete: (_) async {
      completed = true;
    });
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '至少添加一位搭子'))
            .onPressed,
        isNull);
    await tester.drag(find.byType(PageView), const Offset(-290, 0));
    await tester.pumpAndSettle();
    expect(find.text('已添加 0 位', findRichText: true), findsOneWidget);
    await tester.tap(find.text('添加为我的搭子').hitTestable());
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(290, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加为我的搭子').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('已添加 2 位', findRichText: true), findsOneWidget);
    await tester.tap(find.text('选好了，开始聊天'));
    await tester.pumpAndSettle();
    expect(gateway.saved.single, ['b', 'a']);
    expect(completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed save keeps choice and allows retry; remove returns to zero',
      (tester) async {
    final gateway = Gateway()..fail = true;
    await open(tester, gateway);
    await tester.tap(find.text('添加为我的搭子').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('选好了，开始聊天'));
    await tester.pumpAndSettle();
    expect(find.text('未能保存，请重试；已选搭子会保留'), findsOneWidget);
    expect(find.text('已添加 1 位', findRichText: true), findsOneWidget);
    await tester.tap(find.text('✓ 已添加，再点取消').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('至少添加一位搭子'), findsOneWidget);
  });

  testWidgets('local encoded introduction plays; paging replays each voice',
      (tester) async {
    await open(tester, Gateway());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(audio, contains('playPreviewAudio'));
    expect(String.fromCharCodes(playedBytes!.sublist(4, 8)), 'ftyp');
    await tester.drag(find.byType(PageView), const Offset(-290, 0));
    await tester.pumpAndSettle();
    expect(audio.where((method) => method == 'playPreviewAudio').length, 2);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection card and footer fit compact and tall phones',
      (tester) async {
    await open(tester, Gateway());
    for (final size in [
      const Size(960, 1704),
      const Size(960, 1920),
      const Size(1080, 2400),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'viewport $size');
      expect(find.text('至少添加一位搭子').hitTestable(), findsOneWidget);
      expect(find.byTooltip('下一位'), findsOneWidget);
    }
  });
}
