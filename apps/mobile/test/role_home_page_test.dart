import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/role_editor_page.dart';
import 'package:bingo/features/roles/presentation/role_detail_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/roles/presentation/role_home_page.dart';
import 'package:bingo/shared/widgets/partner_action_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/memory_role_order_store.dart';

class _RoleHomeGateway implements RoleGateway {
  int listCalls = 0;
  @override
  Future<List<RoleOption>> listRoles() async {
    listCalls++;
    return const [
      RoleOption(
          id: 'girlfriend',
          name: '女朋友',
          nickname: '甜甜',
          builtin: true,
          description: '关心生活，温柔陪伴',
          messageCount: 15,
          lastMessage: '这段聊天内容不应显示在列表',
          unreadCount: 2),
      RoleOption(
          id: 'boyfriend',
          name: '男朋友',
          nickname: '暖暖',
          builtin: true,
          unreadCount: 120),
      RoleOption(id: 'parent', name: '家长', builtin: true),
      RoleOption(id: 'teacher', name: '老师', builtin: true),
      RoleOption(id: 'child', name: '小孩', builtin: true),
      RoleOption(id: 'colleague', name: '同事', builtin: true),
      RoleOption(id: 'custom', name: '倾听伙伴', builtin: false, prompt: '认真倾听'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'companion header is left aligned with a square logo profile entry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var profileOpened = false;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: Scaffold(
            body: RoleHomePage(
                userId: 'header-test',
                orderStore: MemoryRoleOrderStore(),
                gateway: _RoleHomeGateway(),
                onOpenRole: (_) async {},
                onOpenSettings: () => profileOpened = true))));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('陪伴空间')).dx, 18);
    expect(tester.getTopLeft(find.text('在这里，慢慢聊~')).dx, 18);
    final createStyle = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '创建伙伴'))
        .style!;
    expect(createStyle.backgroundColor!.resolve({}),
        BingoPalette.companionActionSurface);
    expect(createStyle.foregroundColor!.resolve({}),
        BingoPalette.companionActionInk);
    final createIcon = tester.widget<PartnerActionIcon>(find.descendant(
        of: find.widgetWithText(FilledButton, '创建伙伴'),
        matching: find.byType(PartnerActionIcon)));
    expect(createIcon.symbol, PartnerActionSymbol.create);
    expect(createIcon.color, BingoPalette.companionActionIcon);
    expect(createIcon.size, 25);
    expect(find.byIcon(Icons.add_circle_rounded), findsNothing);
    final profile = find.byTooltip('我的');
    final button = tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '我的'));
    expect(button.style?.backgroundColor?.resolve({}), isNull);
    expect(button.style?.side?.resolve({}), isNull);
    expect(find.descendant(of: profile, matching: find.byType(ClipOval)),
        findsNothing);
    final logos = find.byWidgetPredicate((widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName ==
            'assets/images/bingo_logo.png');
    expect(logos, findsOneWidget);
    final background = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('companion-background')));
    expect((background.decoration as BoxDecoration).gradient,
        BingoPalette.companionGlow);
    await tester.tap(profile);
    expect(profileOpened, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long-press drag saves locally and survives refresh and remount',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemoryRoleOrderStore();
    final gateway = _RoleHomeGateway();
    final pageKey = GlobalKey<RoleHomePageState>();
    var opened = false;
    Widget page(String userId) => MaterialApp(
        theme: buildBingoTheme(),
        home: Scaffold(
            body: RoleHomePage(
                key: pageKey,
                userId: userId,
                orderStore: store,
                gateway: gateway,
                onOpenRole: (_) async => opened = true)));
    await tester.pumpWidget(page('account-a'));
    await tester.pumpAndSettle();
    final initialCalls = gateway.listCalls;
    final gesture = await tester.startGesture(
        tester.getTopLeft(find.byKey(const ValueKey('girlfriend'))) +
            const Offset(30, 40));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opened, isFalse);
    expect(gateway.listCalls, initialCalls);
    expect(store.orders['account-a'], isNotNull);
    expect(store.orders['account-a']!.take(2), ['boyfriend', 'girlfriend']);
    expect(tester.getTopLeft(find.text('暖暖')).dy,
        lessThan(tester.getTopLeft(find.text('甜甜')).dy));
    await pageKey.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('暖暖')).dy,
        lessThan(tester.getTopLeft(find.text('甜甜')).dy));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page('account-a'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('暖暖')).dy,
        lessThan(tester.getTopLeft(find.text('甜甜')).dy));
    await tester.pumpWidget(page('account-b'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('甜甜')).dy,
        lessThan(tester.getTopLeft(find.text('暖暖')).dy));
    expect(store.orders['account-b'], isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'role cards open directly and provide creation and private editing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const device = MethodChannel('bingo/device_tools');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(device, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(device, null));
    String? opened;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: Scaffold(
          body: RoleHomePage(
              userId: 'test-user',
              orderStore: MemoryRoleOrderStore(),
              gateway: _RoleHomeGateway(),
              onOpenRole: (role) async => opened = role.id),
        )));
    await tester.pumpAndSettle();
    expect(find.text('陪伴空间'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('甜甜'), findsOneWidget);
    expect(find.text('女朋友 · 关心生活，温柔陪伴'), findsOneWidget);
    expect(find.textContaining('条消息'), findsNothing);
    expect(find.textContaining('这段聊天内容'), findsNothing);
    final badge = tester.getRect(find.text('2'));
    final enter = tester.getRect(find.widgetWithText(TextButton, '进入').first);
    expect(badge.center.dx, greaterThan(enter.center.dx));
    expect(badge.center.dy, lessThan(enter.center.dy));
    await tester.tap(find.text('甜甜'));
    await tester.pumpAndSettle();
    expect(opened, isNull);
    expect(find.byType(RoleDetailPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '进入').first);
    await tester.pumpAndSettle();
    expect(opened, 'girlfriend');
    await tester.scrollUntilVisible(find.text('倾听伙伴'), 400,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('倾听伙伴'));
    await tester.pumpAndSettle();
    expect(find.byType(RoleDetailPage), findsOneWidget);
    await tester.tap(find.byTooltip('编辑伙伴'));
    await tester.pumpAndSettle();
    expect(tester.widget<RoleEditorPage>(find.byType(RoleEditorPage)).role?.id,
        'custom');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('创建伙伴'));
    await tester.tap(find.text('创建伙伴'));
    await tester.pumpAndSettle();
    expect(tester.widget<RoleEditorPage>(find.byType(RoleEditorPage)).role,
        isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
