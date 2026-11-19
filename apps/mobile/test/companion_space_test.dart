import 'package:bingo/core/config/app_config.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('bingo/local_chat'),
          (call) async => call.method == 'loadRoleOrder' ? <String>[] : null));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('bingo/local_chat'), null));
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
      var communityVisits = 0;
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
                  nickname: '一个需要在窄屏上换行的很长很长的用户昵称',
                  onChat: (_) async {},
                  onDetail: (role) async {
                    opened.add(role.id);
                  },
                  onOpenGroup: (_) async {},
                  onCreateGroup: (_) async {},
                  onCreateRole: () async {},
                  onAllGroups: () {},
                  onCommunity: () => communityVisits++,
                  onMessages: () {},
                  onSearchChats: () {}))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('companion-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('companion-card-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('companion-card-4')), findsOneWidget);
      expect(find.text('和搭子1聊聊').hitTestable(), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('和搭子2聊聊').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('上一位搭子'));
      await tester.pumpAndSettle();
      expect(find.text('和搭子1聊聊').hitTestable(), findsOneWidget);
      await tester.tap(find.text('全部 ›').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('搭子10'), 250,
          scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(find.text('搭子10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搭子10'));
      await tester.pumpAndSettle();
      expect(opened, ['10']);
      await tester.ensureVisible(find.text('社区推荐'));
      await tester.tap(find.text('社区推荐'));
      expect(communityVisits, 1);
      expect(find.text('发现搭子', skipOffstage: false), findsNothing);
      expect(find.text('搭子1'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      gateway.close();
    });
  }
}
