import 'dart:async';
import 'package:bingo/core/config/app_config.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/roles/presentation/companion_space_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway extends HttpApiGateway {
  _Gateway()
      : super(
            config: AppConfig(apiBaseUri: Uri.parse('http://localhost:8000')));
  @override
  Future<List<RoleOption>> listRoles() async => [
        for (var i = 1; i <= 10; i++)
          RoleOption(id: '$i', name: '女朋友', nickname: '搭子$i', builtin: true)
      ];
  @override
  Future<List<ChatGroup>> listGroups() async => [];
}

class _Recommendations extends _Gateway {
  Completer<RoleOption>? pending;
  int installs = 0;
  final consumed = <String>{};
  final scopes = <String>[];
  @override
  Future<CommunityPageResult> listCommunity(
      {String query = '',
      String scope = 'all',
      String sort = 'latest',
      int offset = 0}) async {
    scopes.add(scope);
    return CommunityPageResult([
      for (final id in ['first', 'second'])
        if (!consumed.contains(id))
          CommunityShare(
              id: id,
              name: '推荐$id',
              introduction: '认真倾听你的生活',
              authorName: '分享者',
              createdAt: DateTime.utc(2026),
              avatarAsset: 'colleague.png')
    ], null);
  }

  @override
  Future<RoleOption> installCompanion(String id) async {
    installs++;
    final role = await (pending = Completer<RoleOption>()).future;
    consumed.add(id);
    return role;
  }
}

class _DifferentHeightRecommendations extends _Recommendations {
  @override
  Future<CommunityPageResult> listCommunity(
          {String query = '',
          String scope = 'all',
          String sort = 'latest',
          int offset = 0}) async =>
      CommunityPageResult([
        CommunityShare(
            id: 'tall',
            name: 'Rookie',
            introduction: '对线哪里可以处理得更好，怎样把优势带给队友？和 Rookie 一起拆开聊。'
                '发挥不好时也不用急着证明自己，先说说感受，再想下一步。',
            authorName: 'Bingo 社区',
            createdAt: DateTime.utc(2026),
            roleType: '电竞搭子',
            traits: const ['思路清晰', '耐心倾听'],
            avatarAsset: 'colleague.png'),
        CommunityShare(
            id: 'short',
            name: '木木',
            introduction: '我在，慢慢说。',
            authorName: 'Bingo 社区',
            createdAt: DateTime.utc(2026),
            avatarAsset: 'confidant.png')
      ], null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('bingo/local_chat'),
          (call) async => call.method == 'loadRoleOrder' ? <String>[] : null));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('bingo/local_chat'), null));
  for (final scale in [1.0, 1.3]) {
    testWidgets('discovery crossfade preserves outgoing height at scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _DifferentHeightRecommendations();
      await tester.pumpWidget(MaterialApp(
          theme: buildBingoTheme(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: CompanionSpacePage(
                  gateway: gateway,
                  groups: gateway,
                  community: gateway,
                  userId: 'different-height-test',
                  onChat: (_) async {},
                  onDetail: (_) async {},
                  onOpenGroup: (_) async {},
                  onCreateGroup: (_) async {},
                  onCreateRole: () async {},
                  onAllGroups: () {},
                  onCommunity: () {},
                  onMessages: () {},
                  onSearchChats: () {}))));
      await tester.pumpAndSettle();
      final refresh = find.byTooltip('换一个');
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      for (var turn = 0; turn < 4; turn++) {
        await tester.tap(refresh);
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      gateway.close();
    });
  }
  testWidgets('rapid discovery refresh never opens details or overlaps swaps',
      (tester) async {
    final gateway = _Recommendations();
    var details = 0;
    var ready = false;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: Scaffold(
            body: CompanionSpacePage(
                gateway: gateway,
                groups: gateway,
                community: gateway,
                userId: 'rapid-refresh-test',
                onReady: () => ready = true,
                onChat: (_) async {},
                onDetail: (_) async {},
                onOpenGroup: (_) async {},
                onCreateGroup: (_) async {},
                onCreateRole: () async {},
                onRecommendation: (_) async => details++,
                onAllGroups: () {},
                onCommunity: () {},
                onMessages: () {},
                onSearchChats: () {}))));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 30 && !ready; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
    }
    expect(ready, isTrue);
    final refresh = find.byTooltip('换一个');
    await tester.ensureVisible(refresh);
    await tester.pumpAndSettle();
    for (var round = 0; round < 8; round++) {
      for (var tap = 0; tap < 20; tap++) {
        await tester.tap(refresh);
        await tester.pump(const Duration(milliseconds: 15));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(round.isEven ? '推荐second' : '推荐first'), findsOneWidget);
    }
    expect(details, 0);
    expect(gateway.installs, 0);
    expect(gateway.scopes, ['recommended']);
    await tester.pumpWidget(const SizedBox.shrink());
    gateway.close();
  });
  testWidgets(
      'discovery keeps failed recommendation and advances only after successful install',
      (tester) async {
    final gateway = _Recommendations();
    var communityVisits = 0;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: Scaffold(
            body: CompanionSpacePage(
                gateway: gateway,
                groups: gateway,
                community: gateway,
                userId: 'recommendation-test',
                onChat: (_) async {},
                onDetail: (_) async {},
                onOpenGroup: (_) async {},
                onCreateGroup: (_) async {},
                onCreateRole: () async {},
                onAllGroups: () {},
                onCommunity: () => communityVisits++,
                onMessages: () {},
                onSearchChats: () {}))));
    await tester.pumpAndSettle();
    expect(gateway.scopes, ['recommended']);
    await tester.tap(find.byTooltip('换一个'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('推荐first'), findsOneWidget);
    expect(find.text('推荐second'), findsOneWidget);
    expect(find.byKey(const ValueKey('recommend-add-first')).hitTestable(),
        findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('推荐second'), findsOneWidget);
    expect(gateway.installs, 0);
    expect(communityVisits, 0);
    await tester.tap(find.byTooltip('换一个'));
    await tester.pumpAndSettle();
    expect(find.text('推荐first'), findsOneWidget);
    final first = find.byKey(const ValueKey('recommend-add-first'));
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pump();
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pump();
    expect(gateway.installs, 1);
    expect(find.text('推荐first'), findsOneWidget);
    gateway.pending!.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('推荐first'), findsOneWidget);
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pump();
    gateway.pending!.complete(const RoleOption(
        id: 'copy-one',
        name: '新搭子',
        builtin: false,
        sourcePublicationId: 'first'));
    await tester.pumpAndSettle();
    expect(find.text('推荐first'), findsNothing);
    expect(find.text('推荐second'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recommend-add-second')));
    await tester.pump();
    gateway.pending!.complete(const RoleOption(
        id: 'copy-two',
        name: '另一个搭子',
        builtin: false,
        sourcePublicationId: 'second'));
    await tester.pumpAndSettle();
    expect(find.text('去社区发现更多有趣的搭子'), findsOneWidget);
    expect(find.text('推荐first'), findsNothing);
    expect(gateway.scopes.every((scope) => scope == 'recommended'), true);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    gateway.close();
  });
  for (final width in [320.0, 360.0]) {
    testWidgets(
        'home preview opens the full directory for every companion at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _Gateway();
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp(
          theme: buildBingoTheme(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!),
          home: Scaffold(
              body: CompanionSpacePage(
                  gateway: gateway,
                  groups: gateway,
                  userId: 'strip-test',
                  onChat: (_) async {},
                  onDetail: (role) async {
                    opened.add(role.id);
                  },
                  onOpenGroup: (_) async {},
                  onCreateGroup: (_) async {},
                  onCreateRole: () async {},
                  onAllGroups: () {},
                  onCommunity: () {},
                  onMessages: () {},
                  onSearchChats: () {}))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('companion-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('companion-card-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('companion-card-4')), findsOneWidget);
      await tester.tap(find.text('全部 ›').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('搭子10'), 250,
          scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(find.text('搭子10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搭子10'));
      await tester.pumpAndSettle();
      expect(opened, ['10']);
      expect(find.text('搭子1'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      gateway.close();
    });
  }
}
