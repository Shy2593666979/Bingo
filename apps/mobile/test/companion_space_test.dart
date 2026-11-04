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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('bingo/local_chat'),
          (call) async => call.method == 'loadRoleOrder' ? <String>[] : null));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('bingo/local_chat'), null));
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
    await tester.tap(find.text('换一个'));
    await tester.pumpAndSettle();
    expect(find.text('推荐second'), findsOneWidget);
    expect(gateway.installs, 0);
    expect(communityVisits, 0);
    await tester.tap(find.text('换一个'));
    await tester.pumpAndSettle();
    expect(find.text('推荐first'), findsOneWidget);
    final first = find.byKey(const ValueKey('recommend-add-first'));
    await tester.tap(first);
    await tester.pump();
    await tester.tap(first);
    await tester.pump();
    expect(gateway.installs, 1);
    expect(find.text('推荐first'), findsOneWidget);
    gateway.pending!.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('推荐first'), findsOneWidget);
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
    testWidgets('compact home strip reaches every companion at $width',
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
      expect(
          tester.getSize(find.byKey(const ValueKey('companion-card-1'))).width,
          lessThan(130));
      final strip = find.byKey(const ValueKey('companion-strip-0'));
      await tester.dragUntilVisible(
          find.text('搭子10'), strip, const Offset(-180, 0));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('搭子10'));
      await tester.tap(find.text('搭子10'));
      expect(opened, ['10']);
      await tester.drag(strip, const Offset(4000, 0));
      await tester.pumpAndSettle();
      expect(find.text('搭子1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      gateway.close();
    });
  }
}
