import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/presentation/role_editor_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RoleGateway implements RoleGateway {
  String? savedName;
  String? savedVoice;
  String? savedRoleType;
  String? savedPersonality;
  String? savedBackground, savedSpeakingStyle;
  List<String>? savedCategories;
  List<String>? savedTraits;

  @override
  Future<RoleOption> saveRole(
      {String? id,
      required String name,
      required String prompt,
      String? background,
      String? speakingStyle,
      String? relationship,
      List<String>? personalityTags,
      String? roleType,
      String? personality,
      String? avatarData,
      String? voiceSourceId,
      String? description,
      String? openingLine,
      List<String>? categories,
      List<String>? traits,
      bool draft = false}) async {
    savedName = name;
    savedVoice = voiceSourceId;
    savedRoleType = relationship ?? roleType;
    savedPersonality = personality;
    savedBackground = background;
    savedSpeakingStyle = speakingStyle;
    savedCategories = categories;
    savedTraits = personalityTags ?? traits;
    return RoleOption(
        id: id ?? 'new-role',
        name: name,
        builtin: false,
        prompt: prompt,
        background: background,
        speakingStyle: speakingStyle);
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
        .widget<FilledButton>(find.widgetWithText(FilledButton, '创建搭子'))
        .style!;
    expect(createStyle.backgroundColor!.resolve({}), BingoPalette.primary);
    expect(createStyle.foregroundColor!.resolve({}), Colors.white);
    final description = find.descendant(
        of: find.byKey(const ValueKey('role-background')),
        matching: find.byType(TextField));
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
    await tester.tap(find.text('人物声音'));
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
    await tester.scrollUntilVisible(find.text('性格标签'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('性格标签'));
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.text('展开更多标签'));
    await tester.tap(find.text('展开更多标签'));
    await tester.pumpAndSettle();
    expect(find.text('收起更多标签'), findsOneWidget);
    expect(find.text('工作搭子'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'creation includes introduction and opening and keeps its action visible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: RoleEditorPage(gateway: _RoleGateway(), roles: const [])));
    for (final label in [
      '人物头像',
      '人物名称',
      '人物关系',
      '说话风格',
      '性格标签',
      '人物背景',
      '人物声音'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('一句话介绍'), findsNothing);
    expect(find.text('开场白'), findsNothing);
    final action = find.widgetWithText(FilledButton, '创建搭子');
    expect(tester.getRect(action).bottom, lessThanOrEqualTo(800));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('系统音色'), findsNothing);
    expect(find.text('已有搭子'), findsNothing);
    expect(find.text('角色分类'), findsNothing);
    await tester.scrollUntilVisible(find.text('更多资料'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多资料'));
    await tester.pumpAndSettle();
    expect(find.text('一句话介绍'), findsOneWidget);
    expect(find.text('开场白'), findsOneWidget);
    expect(find.text('暂无可用的搭子音色，可以通过录音创建。'), findsOneWidget);
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
    expect(find.text('上传头像'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('role-name')), '倾听搭子');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('role-background')), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.byKey(const ValueKey('role-background')), '住在海边，喜欢读书');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('voice-selector')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('voice-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-selector')));
    await tester.pumpAndSettle();
    expect(find.text('系统音色'), findsNothing);
    expect(find.text('已有搭子'), findsNothing);
    expect(find.byKey(const ValueKey('voice-option-system')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('voice-option-system')),
            matching: find.byType(AssistantAvatar)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('voice-option-mine')),
            matching: find.byType(AssistantAvatar)),
        findsOneWidget);
    final voiceImage = tester.widget<Image>(find
        .descendant(
            of: find.byKey(const ValueKey('voice-option-mine')),
            matching: find.byType(Image))
        .first);
    final provider = voiceImage.image;
    expect(
        ((provider is ResizeImage ? provider.imageProvider : provider)
                as AssetImage)
            .assetName,
        'assets/images/bingo_logo.webp');
    await tester.tap(find.byKey(const ValueKey('voice-option-mine')));
    await tester.pumpAndSettle();
    expect(find.text('我的姐姐'), findsOneWidget);
    expect(find.text('当前音色：我的姐姐'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '创建搭子'));
    await tester.tap(find.widgetWithText(FilledButton, '创建搭子'));
    await tester.pumpAndSettle();
    expect(gateway.savedName, '倾听搭子');
    expect(gateway.savedVoice, 'mine');
    expect(gateway.savedCategories, isNull);
    expect(gateway.savedTraits, hasLength(2));
    expect(gateway.savedRoleType, '陪伴伙伴');
    expect(gateway.savedPersonality, '温柔体贴');
    expect(gateway.savedSpeakingStyle, '温柔体贴');
    expect(gateway.savedBackground, '住在海边，喜欢读书');
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
    expect(find.text('说话风格'), findsOneWidget);
    expect(find.text('搭子设定'), findsNothing);
    expect(find.text('删除搭子'), findsNothing);
    expect(find.text('清空'), findsNothing);
    expect(find.text('选填'), findsNothing);
    for (final key in ['role-name', 'role-relationship', 'role-background']) {
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(TextField)))
              .readOnly,
          isTrue);
    }
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const ValueKey('role-speaking-style')),
                matching: find.byType(TextField)))
            .readOnly,
        isFalse);
    await tester.ensureVisible(find.text('幽默风趣'));
    await tester.tap(find.text('幽默风趣'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pumpAndSettle();
    expect(gateway.savedPersonality, '幽默风趣');
    expect(gateway.savedSpeakingStyle, '幽默风趣');
    expect(gateway.savedName, '甜甜');
    expect(tester.takeException(), isNull);
  });
}
