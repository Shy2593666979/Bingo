import 'package:bingo/features/voices/data/voice_gateway.dart';
import 'package:bingo/features/voices/models/voice_option.dart';
import 'package:bingo/features/voices/presentation/voice_library_page.dart';
import 'package:bingo/features/voices/presentation/voice_cover.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/presentation/role_editor_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RoleGateway implements RoleGateway, VoiceGateway {
  @override
  Future<List<VoiceOption>> listVoices({String? scope, String? gender}) async =>
      const [
        VoiceOption(
            id: 'voice-system',
            name: '清晰女声',
            scope: 'system',
            status: 'ready',
            hasAudio: true),
        VoiceOption(
            id: 'voice-private',
            name: '自己的声音',
            scope: 'private',
            status: 'ready',
            hasAudio: true,
            editable: true),
        VoiceOption(
            id: 'voice-community',
            name: '社区声音',
            scope: 'community',
            status: 'ready',
            hasAudio: true),
      ];
  @override
  Future<Uint8List> previewVoice(String id) async => Uint8List(44);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
      String? voiceId,
      String? description,
      List<String>? categories,
      List<String>? traits,
      bool draft = false}) async {
    savedName = name;
    savedVoice = voiceId;
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

Future<void> _nextStep(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '下一步'));
  await tester.pumpAndSettle();
}

Future<void> _goToStep(WidgetTester tester, int target) async {
  await tester.enterText(find.byKey(const ValueKey('role-name')), '倾听搭子');
  for (var i = 0; i < target; i++) {
    if (i == 3) {
      await tester.enterText(
          find.byKey(const ValueKey('role-background')), '住在海边，喜欢读书');
    }
    await _nextStep(tester);
  }
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
        .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
        .style!;
    expect(createStyle.backgroundColor!.resolve({}), BingoPalette.primary);
    expect(createStyle.foregroundColor!.resolve({}), Colors.white);
    await _goToStep(tester, 3);
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

  testWidgets(
      'voice field opens the standalone library and returns the selected asset',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: RoleEditorPage(gateway: _RoleGateway(), roles: const [])));
    await tester.pumpAndSettle();
    await _goToStep(tester, 4);
    final selector = find.byKey(const ValueKey('voice-selector'));
    await tester.scrollUntilVisible(selector, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.byType(VoiceLibraryPage), findsOneWidget);
    await tester.tap(find.text('我的音色'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-asset-voice-private')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用此音色'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceLibraryPage), findsNothing);
    expect(find.text('当前音色：自己的声音'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('traits are inline, expandable and limited to three selections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: RoleEditorPage(gateway: _RoleGateway(), roles: const [])));
    await _goToStep(tester, 2);
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
      'creation keeps the optional introduction without a manual greeting field',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: RoleEditorPage(gateway: _RoleGateway(), roles: const [])));
    expect(find.text('1 / 5'), findsOneWidget);
    await _nextStep(tester);
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('请填写此项人物资料'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('role-name')), '倾听搭子');
    expect(find.text('人物名称'), findsOneWidget);
    expect(find.text('人物关系'), findsOneWidget);
    await _nextStep(tester);
    expect(find.text('2 / 5'), findsOneWidget);
    await _nextStep(tester);
    expect(find.text('3 / 5'), findsOneWidget);
    await _nextStep(tester);
    expect(find.text('4 / 5'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('role-background')), '住在海边，喜欢读书');
    await _nextStep(tester);
    expect(find.text('5 / 5'), findsOneWidget);
    await tester.tap(find.byTooltip('上一步'));
    await tester.pumpAndSettle();
    expect(find.text('住在海边，喜欢读书'), findsOneWidget);
    await _nextStep(tester);
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
    expect(find.text('开场白'), findsNothing);
    expect(find.byKey(const ValueKey('role-opening')), findsNothing);
    expect(find.text('创建新音色'), findsOneWidget);
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
    await _goToStep(tester, 4);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('voice-selector')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('voice-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-selector')));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceLibraryPage), findsOneWidget);
    await tester.tap(find.text('我的音色'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceCover), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('voice-asset-voice-private')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用此音色'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '创建搭子'));
    await tester.pumpAndSettle();
    expect(gateway.savedName, '倾听搭子');
    expect(gateway.savedVoice, 'voice-private');
    expect(gateway.savedCategories, isNull);
    expect(gateway.savedTraits, hasLength(2));
    expect(gateway.savedRoleType, '陪伴伙伴');
    expect(gateway.savedPersonality, '温柔体贴');
    expect(gateway.savedSpeakingStyle, '温柔体贴');
    expect(gateway.savedBackground, '住在海边，喜欢读书');
  });

  testWidgets(
      'community copy keeps its voice when the source is not a default companion',
      (tester) async {
    final gateway = _RoleGateway();
    const role = RoleOption(
        id: 'community-copy',
        name: '老雷',
        builtin: false,
        roleType: '董事长',
        background: '一位虚构的董事长。',
        speakingStyle: '幽默风趣',
        voiceSourceId: 'hidden-community-source',
        voiceId: 'voice-community',
        voiceName: '社区声音');
    await tester.pumpWidget(MaterialApp(
        home:
            RoleEditorPage(gateway: gateway, roles: const [role], role: role)));
    expect(find.text('当前音色：社区声音'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pumpAndSettle();
    expect(gateway.savedName, '老雷');
    expect(gateway.savedVoice, 'voice-community');
    expect(tester.takeException(), isNull);
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
