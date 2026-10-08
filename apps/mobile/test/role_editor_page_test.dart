import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/presentation/role_editor_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RoleGateway implements RoleGateway {
  String? savedName;
  String? savedVoice;
  String? savedRoleType;
  String? savedPersonality;
  List<String>? savedCategories;
  List<String>? savedTraits;

  @override
  Future<RoleOption> saveRole(
      {String? id,
      required String name,
      required String prompt,
      String? roleType,
      String? personality,
      String? avatarData,
      String? voiceSourceId,
      List<String>? categories,
      List<String>? traits,
      bool draft = false}) async {
    savedName = name;
    savedVoice = voiceSourceId;
    savedRoleType = roleType;
    savedPersonality = personality;
    savedCategories = categories;
    savedTraits = traits;
    return RoleOption(
        id: id ?? 'new-role', name: name, builtin: false, prompt: prompt);
  }

  @override
  Future<List<RoleOption>> listRoles() async => [];
  @override
  Future<void> deleteRole(String id) async {}
  @override
  Future<String> cloneRoleVoice(String id, Uint8List audio) async => 'job';
  @override
  Future<Map<String, dynamic>> voiceJob(String id) async => {'status': 'ready'};
  @override
  Future<Uint8List> previewRoleVoice(String id) async => Uint8List(44);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = MethodChannel('bingo/device_tools');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => messenger.setMockMethodCallHandler(device, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(device, null));

  testWidgets('partner description keeps its limit without showing a counter',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: RoleEditorPage(gateway: _RoleGateway(), roles: const [])));
    final createStyle = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '创建伙伴'))
        .style!;
    expect(createStyle.backgroundColor!.resolve({}),
        BingoPalette.companionActionSurface);
    expect(createStyle.foregroundColor!.resolve({}),
        BingoPalette.companionActionInk);
    final description = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'TA 是谁？怎样说话？你希望 TA 怎样陪伴你？');
    await tester.scrollUntilVisible(description, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(description);
    expect(field.maxLength, 2000);
    expect(field.decoration?.counterText, '');
    expect(find.text('0/2000'), findsNothing);
  });

  testWidgets('voice options expand below the field without a popup route',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: RoleEditorPage(gateway: _RoleGateway(), roles: const [
      RoleOption(id: 'girl', name: '甜甜', builtin: true),
      RoleOption(id: 'boy', name: '暖暖', builtin: true),
    ])));
    final selector = find.byKey(const ValueKey('voice-selector'));
    final options = find.byKey(const ValueKey('voice-options'));
    await tester.scrollUntilVisible(selector, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final barrierCount = find.byType(ModalBarrier).evaluate().length;
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(options, findsOneWidget);
    expect(tester.getRect(options).top,
        greaterThanOrEqualTo(tester.getRect(selector).bottom));
    expect(find.byType(ModalBarrier).evaluate().length, barrierCount);
    await tester.tap(find.byKey(const ValueKey('voice-option-boy')));
    await tester.pumpAndSettle();
    expect(options, findsNothing);
    expect(find.text('当前音色：暖暖'), findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('伙伴声音'));
    await tester.pumpAndSettle();
    expect(options, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('traits are inline, expandable and limited to three selections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: RoleEditorPage(gateway: _RoleGateway(), roles: const [])));
    await tester.ensureVisible(find.text('主动关心'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主动关心'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 / 3'), findsOneWidget);
    await tester.tap(find.text('温柔体贴').last);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 / 3'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.ensureVisible(find.text('展开更多特征'));
    await tester.tap(find.text('展开更多特征'));
    await tester.pumpAndSettle();
    expect(find.text('收起更多特征'), findsOneWidget);
    expect(find.text('工作搭子'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact creation has no categories and keeps its action visible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: RoleEditorPage(gateway: _RoleGateway(), roles: const [])));
    expect(find.textContaining('分类'), findsNothing);
    expect(find.text('伙伴昵称'), findsOneWidget);
    final action = find.widgetWithText(FilledButton, '创建伙伴');
    expect(tester.getRect(action).bottom, lessThanOrEqualTo(800));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('系统音色'), findsNothing);
    expect(find.text('已有伙伴'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(tester.getRect(action).bottom, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('creation can reuse a private voice and keeps the default logo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _RoleGateway();
    await tester.pumpWidget(MaterialApp(
        home: RoleEditorPage(gateway: gateway, roles: const [
      RoleOption(id: 'system', name: '女朋友', builtin: true),
      RoleOption(
          id: 'mine',
          name: '我的姐姐',
          builtin: false,
          hasClonedVoice: true,
          voiceSourceId: 'mine'),
    ])));
    expect(
        tester.widget<Image>(find.byType(Image).first).image,
        isA<AssetImage>().having((image) => image.assetName, 'asset',
            'assets/images/bingo_logo.png'));
    expect(tester.widget<Icon>(find.byIcon(Icons.photo_camera_outlined)).color,
        BingoPalette.avatarButtonInk);
    await tester.enterText(find.byType(TextFormField).at(0), '倾听伙伴');
    await tester.enterText(find.byType(TextFormField).at(2), '耐心倾听，温柔陪伴');
    await tester.ensureVisible(find.byKey(const ValueKey('voice-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-selector')));
    await tester.pumpAndSettle();
    expect(find.text('系统音色'), findsNothing);
    expect(find.text('已有伙伴'), findsNothing);
    expect(find.byKey(const ValueKey('voice-option-system')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('voice-option-system')),
            matching: find.byType(AssistantAvatar)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('voice-option-mine')),
            matching: find.byType(UserAvatar)),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice-option-mine')));
    await tester.pumpAndSettle();
    expect(find.text('我的姐姐'), findsOneWidget);
    expect(find.text('当前音色：我的姐姐'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '创建伙伴'));
    await tester.tap(find.widgetWithText(FilledButton, '创建伙伴'));
    await tester.pumpAndSettle();
    expect(gateway.savedName, '倾听伙伴');
    expect(gateway.savedVoice, 'mine');
    expect(gateway.savedCategories, isNull);
    expect(gateway.savedTraits, hasLength(2));
    expect(gateway.savedRoleType, '');
    expect(gateway.savedPersonality, '温柔体贴');
    expect(find.textContaining('分类'), findsNothing);
  });

  testWidgets('built-in partners can edit personality but not shared identity',
      (tester) async {
    final gateway = _RoleGateway();
    const role = RoleOption(
        id: 'girl',
        name: '女朋友',
        nickname: '甜甜',
        builtin: true,
        personality: '温柔体贴');
    await tester.pumpWidget(MaterialApp(
        home:
            RoleEditorPage(gateway: gateway, roles: const [role], role: role)));
    expect(find.text('伙伴性格'), findsOneWidget);
    expect(find.text('伙伴设定'), findsNothing);
    expect(find.text('删除伙伴'), findsNothing);
    expect(find.text('清空'), findsNothing);
    expect(find.text('选填'), findsNothing);
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields.every((field) => field.enabled == false), isTrue);
    await tester.ensureVisible(find.text('幽默风趣'));
    await tester.tap(find.text('幽默风趣'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pumpAndSettle();
    expect(gateway.savedPersonality, '幽默风趣');
    expect(gateway.savedName, '甜甜');
    expect(tester.takeException(), isNull);
  });
}
