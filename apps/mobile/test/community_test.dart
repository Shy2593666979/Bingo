import 'dart:async';

import 'package:bingo/core/config/app_config.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/features/conversations/presentation/messages_page.dart';
import 'package:bingo/features/app_shell.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_page.dart';
import 'package:bingo/features/roles/presentation/role_detail_page.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_page.dart';
import 'package:bingo/features/community/presentation/community_detail_page.dart';
import 'package:bingo/features/community/presentation/publish_companion_page.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/group_chat/presentation/create_center_page.dart';
import 'package:bingo/features/settings/presentation/reference_my_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = UserProfile(
    id: 'alice',
    phone: '19900000000',
    username: '小林',
    assistantName: '甜甜',
    personality: '温柔体贴',
    role: '女朋友',
    onboardingComplete: true);
const _role = RoleOption(
    id: 'copy-id',
    name: '星野',
    builtin: false,
    roleType: '朋友',
    prompt: '喜欢星星，擅长倾听');

CommunityShare _share(
        {String name = '星野', String? installed, bool mine = false}) =>
    CommunityShare(
        id: 'share-one',
        name: name,
        introduction: '一起看星星，聊聊今天的小事。',
        authorName: '小林',
        createdAt: DateTime(2026, 10, 29),
        avatarAsset: 'boyfriend.png',
        installedRoleId: installed,
        mine: mine,
        traits: ['善于倾听', '陪伴聊天'],
        persona: {'prompt': '喜欢星星，擅长倾听'});

class _Gateway extends HttpApiGateway {
  _Gateway()
      : super(
            config: AppConfig(apiBaseUri: Uri.parse('http://localhost:8000')));
  CommunityShare share = _share();
  @override
  Future<Map<String, dynamic>> welcomeStatus() async =>
      {'pending': false, 'failed': 0};
  bool failPublish = true;
  final requests = <String>[];
  int installs = 0;
  int itemCount = 1;
  Completer<RoleOption>? pendingInstall;
  final searches = <String, Completer<CommunityPageResult>>{};
  bool deferredSearch = false;
  @override
  Future<void> clearCurrentRegion() async {}
  @override
  Future<List<ChatGroup>> listGroups() async => [];
  @override
  Future<List<RoleOption>> listRoles() async => [_role];
  @override
  Future<UserProfile> getProfile() async => _profile;
  @override
  Future<ConversationSummary> openRoleConversation(String roleId) async =>
      ConversationSummary(
          id: 'private-chat',
          title: '星野',
          roleId: roleId,
          createdAt: DateTime.utc(2026, 11, 3));
  @override
  Future<void> markConversationRead(String id) async {}
  @override
  Future<CommunityPageResult> listCommunity(
      {String query = '',
      String scope = 'all',
      String sort = 'latest',
      int offset = 0}) async {
    if (deferredSearch && query.isNotEmpty) {
      return (searches[query] = Completer<CommunityPageResult>()).future;
    }
    return CommunityPageResult(List.generate(itemCount, (_) => share), null);
  }

  @override
  Future<CommunityShare> getCommunityShare(String id) async => share;
  @override
  Future<RoleOption> installCompanion(String id) async {
    installs++;
    final role = pendingInstall == null ? _role : await pendingInstall!.future;
    share = _share(installed: role.id);
    return role;
  }

  @override
  Future<CommunityShare> publishCompanionDetail(
          {required String roleId,
          required String introduction,
          required String requestId,
          String title = '',
          List<String> shareTags = const [],
          List<String> images = const []}) =>
      publishCompanion(
          roleId: roleId,
          introduction: introduction,
          requestId: requestId,
          images: images);
  @override
  Future<CommunityShare> publishCompanion(
      {required String roleId,
      required String introduction,
      required String requestId,
      List<String> images = const []}) async {
    requests.add(requestId);
    if (failPublish) throw const ApiException('连接中断');
    return share;
  }
}

class _ChatGateway implements ChatGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [320.0, 360.0]) {
    testWidgets('H2 profile portrait strip fits at $width with larger text',
        (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _Gateway();
      await tester.pumpWidget(MaterialApp(
          theme: buildBingoTheme(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!),
          home: Scaffold(
              body: ReferenceMyPage(
                  profile: _profile,
                  roles: gateway,
                  groups: gateway,
                  community: gateway,
                  onEdit: () async {},
                  onSettings: () async {},
                  onShares: () {},
                  onFavorites: () {},
                  onRole: (_) async {},
                  onGroup: (_) async {},
                  onShare: (_) async {},
                  onCreate: () async {},
                  onPartners: () {}))));
      await tester.pumpAndSettle();
      expect(find.text('我的搭子'), findsOneWidget);
      expect(find.text('属于你的陪伴空间'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      gateway.close();
    });
  }
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('bingo/local_chat'),
        (call) async => call.method == 'loadRoleOrder' ? <String>[] : null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/appearance'), (_) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/region_location'),
        (call) async => call.method == 'getEnabled' ? false : null);
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'bingo/local_chat',
      'bingo/appearance',
      'bingo/region_location'
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  Future<void> size(WidgetTester tester,
      {double width = 360, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('community sharing feed fits narrow screens with larger text',
      (tester) async {
    await size(tester, width: 320);
    final gateway = _Gateway()..itemCount = 3;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: Scaffold(
            body: CommunityPage(
                gateway: gateway,
                referenceDesign: true,
                onPublish: () async {},
                onInstalled: (_) async {},
                onOpenCopy: (_) async {}))));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('搜索社区'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byTooltip('搜索社区'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('群聊模板'), findsNothing);
    expect(find.text('加入群聊'), findsNothing);
    expect(find.byTooltip('分享搭子'), findsOneWidget);
    expect(find.text('我的分享'), findsOneWidget);
    expect(find.text('Bingo 搭子'), findsNothing);
    expect(find.text('分享我的搭子 · 星野'), findsWidgets);
    expect(find.text('小林'), findsWidgets);
    expect(find.text('+ 添加搭子'), findsWidgets);
    await tester.tap(find.text('我的收藏'));
    await tester.pumpAndSettle();
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('热门搭子'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await close(tester);
    gateway.close();
  });

  testWidgets(
      'four destinations and independent plus menu preserve the current page',
      (tester) async {
    await size(tester, width: 320);
    final gateway = _Gateway();
    final controller = ChatController(gateway: _ChatGateway());
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: AppShell(
            chatController: controller,
            gateway: gateway,
            profile: _profile,
            callCaptionsEnabled: true,
            onCallCaptionsChanged: (_) async {},
            onProfileSaved: (_) {},
            onLogout: () {})));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('社区'), findsOneWidget);
    await tester.tap(find.byTooltip('查找聊天'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '搜索搭子或聊天记录'), findsOneWidget);
    expect(find.byTooltip('新建'), findsNothing);
    expect(find.text('创建'), findsNothing);
    await tester.enterText(find.byType(TextField), '旧搜索');
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部 ›').last);
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('社区').last);
    await tester.pumpAndSettle();
    expect(find.text('我的分享'), findsOneWidget);
    expect(find.text('发现更多有趣的 AI 搭子～'), findsNothing);
    expect(find.text('发现搭子'), findsNothing);
    await tester.tap(find.bySemanticsLabel('创建中心'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateCenterPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ReferenceNavigation>(find.byType(ReferenceNavigation))
            .selected,
        2);
    expect(find.byType(CommunityPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
    controller.dispose();
    gateway.close();
  });

  testWidgets(
      'chat avatar opens own detail and its chat action returns to the same page',
      (tester) async {
    await size(tester);
    final gateway = _Gateway();
    final controller = ChatController(gateway: _ChatGateway());
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: AppShell(
            chatController: controller,
            gateway: gateway,
            profile: _profile,
            callCaptionsEnabled: true,
            onCallCaptionsChanged: (_) async {},
            onProfileSaved: (_) {},
            onLogout: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('星野').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入聊天'));
    await tester.pumpAndSettle();
    final chat = tester.state(find.byType(ChatPage));
    await tester.tap(find.byKey(const ValueKey('chat-header-avatar')));
    await tester.pumpAndSettle();
    expect(tester.widget<RoleDetailPage>(find.byType(RoleDetailPage)).role.id,
        _role.id);
    await tester.tap(find.text('进入聊天'));
    await tester.pumpAndSettle();
    expect(find.byType(RoleDetailPage), findsNothing);
    expect(tester.state(find.byType(ChatPage)), same(chat));
    await tester.tap(find.byTooltip('返回角色'));
    await tester.pumpAndSettle();
    await close(tester);
    controller.dispose();
    gateway.close();
  });

  testWidgets('main pages swipe in order and keep the visited message state',
      (tester) async {
    await size(tester);
    final gateway = _Gateway();
    final controller = ChatController(gateway: _ChatGateway());
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: AppShell(
            chatController: controller,
            gateway: gateway,
            profile: _profile,
            callCaptionsEnabled: true,
            onCallCaptionsChanged: (_) async {},
            onProfileSaved: (_) {},
            onLogout: () {})));
    await tester.pumpAndSettle();
    final pages = find.byKey(const ValueKey('main-pages'));
    int current() => tester
        .widget<ReferenceNavigation>(find.byType(ReferenceNavigation))
        .selected;
    expect(current(), 0);
    await tester.drag(pages, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(current(), 1);
    final messageState = tester.state(find.byType(MessagesPage));
    for (final index in [2, 3]) {
      await tester.drag(pages, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(current(), index);
    }
    for (final index in [2, 1]) {
      await tester.drag(pages, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(current(), index);
    }
    expect(tester.state(find.byType(MessagesPage)), same(messageState));
    await tester.tap(find.text('首页').last);
    await tester.pumpAndSettle();
    expect(current(), 0);
    expect(tester.widget<PageView>(pages).controller!.page, 0);
    await close(tester);
    controller.dispose();
    gateway.close();
  });

  testWidgets(
      'community cards fit 320px and larger text; duplicate add is prevented',
      (tester) async {
    await size(tester, width: 320);
    final gateway = _Gateway()..pendingInstall = Completer<RoleOption>();
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: Scaffold(
            body: CommunityPage(
                gateway: gateway,
                onPublish: () async {},
                onInstalled: (_) async {},
                onOpenCopy: (_) async {}))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('加入我的搭子'));
    await tester.tap(find.text('加入我的搭子'));
    await tester.pump();
    expect(gateway.installs, 1);
    await tester.tap(find.text('正在加入…'));
    await tester.pump();
    expect(gateway.installs, 1);
    gateway.pendingInstall!.complete(_role);
    await tester.pumpAndSettle();
    expect(find.text('查看我的副本'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
    gateway.close();
  });

  testWidgets('out-of-order search cannot replace newer results',
      (tester) async {
    await size(tester);
    final gateway = _Gateway()..deferredSearch = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommunityPage(
                gateway: gateway,
                onPublish: () async {},
                onInstalled: (_) async {},
                onOpenCopy: (_) async {}))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 400));
    gateway.searches['new']!
        .complete(CommunityPageResult([_share(name: '新结果')], null));
    await tester.pumpAndSettle();
    gateway.searches['old']!
        .complete(CommunityPageResult([_share(name: '旧结果')], null));
    await tester.pumpAndSettle();
    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
    await close(tester);
    gateway.close();
  });

  testWidgets('publish retains retry id until content changes', (tester) async {
    await size(tester);
    final gateway = _Gateway();
    await tester.pumpWidget(MaterialApp(
        home: PublishCompanionPage(
            gateway: gateway, roleGateway: gateway, initialRole: _role)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '一起看星星');
    await tester.tap(find.text('发布分享'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('发布分享'));
    await tester.pumpAndSettle();
    expect(gateway.requests[0], gateway.requests[1]);
    await tester.pump(const Duration(seconds: 3));
    await tester.enterText(find.byType(TextFormField).last, '改过的搭子介绍');
    await tester.tap(find.text('发布分享'));
    await tester.pumpAndSettle();
    expect(gateway.requests[2], isNot(gateway.requests[1]));
    await close(tester);
    gateway.close();
  });

  testWidgets('detail opens the independent editable copy after adding',
      (tester) async {
    await size(tester);
    final gateway = _Gateway();
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: CommunityDetailPage(
            gateway: gateway,
            shareId: 'share-one',
            onInstalled: (_) async {},
            onOpenCopy: (id) async {
              opened = id;
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加为我的搭子'));
    await tester.pumpAndSettle();
    expect(find.text('试聊'), findsNothing);
    expect(find.text('加入群聊'), findsNothing);
    await tester.tap(find.text('进入聊天'));
    await tester.pumpAndSettle();
    expect(opened, 'copy-id');
    await close(tester);
    gateway.close();
  });
}
