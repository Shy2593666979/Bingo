import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/voices/data/voice_gateway.dart';
import 'package:bingo/features/voices/models/voice_option.dart';
import 'package:bingo/features/voices/presentation/voice_editor_page.dart';
import 'package:bingo/features/voices/presentation/voice_library_page.dart';
import 'package:bingo/features/voices/presentation/voice_cover.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Assets implements VoiceGateway, RoleGateway {
  final assets = <VoiceOption>[
    const VoiceOption(
        id: 'asset-system',
        name: '独立男声',
        scope: 'system',
        gender: 'male',
        status: 'ready',
        hasAudio: true),
    const VoiceOption(
        id: 'asset-mine',
        name: '我的轻柔声音',
        scope: 'private',
        status: 'ready',
        hasAudio: true,
        editable: true),
    const VoiceOption(
        id: 'asset-community',
        name: '社区低沉声音',
        scope: 'community',
        status: 'ready',
        hasAudio: true),
  ];
  int roleLoads = 0, created = 0;
  final assignments = <(String, String)>[];
  final preview = Completer<Uint8List>();
  final previews = <String>[];
  @override
  Future<List<VoiceOption>> listVoices({String? scope, String? gender}) async =>
      List.of(assets);
  @override
  Future<Uint8List> previewVoice(String id) {
    previews.add(id);
    return preview.future;
  }

  @override
  Future<List<RoleOption>> listRoles() async {
    roleLoads++;
    return const [
      RoleOption(id: 'role-A', name: '女朋友', nickname: '测试搭子', builtin: true)
    ];
  }

  @override
  Future<VoiceOption> createVoice(
      {required String name,
      String description = '',
      String gender = 'unknown'}) async {
    created++;
    final asset = VoiceOption(
        id: 'asset-created',
        name: name,
        description: description,
        gender: gender,
        editable: true);
    assets.add(asset);
    return asset;
  }

  @override
  Future<void> assignRoleVoice(String roleId, String voiceId) async =>
      assignments.add((roleId, voiceId));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final played = <String>[];
  setUp(() {
    played.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('bingo/device_tools'),
            (call) async {
      played.add(call.method);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), null));
  Future<void> mount(WidgetTester tester, _Assets gateway) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: VoiceLibraryPage(gateway: gateway, roles: gateway)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'independent catalog loads all scopes without looking up roles or their portraits',
      (tester) async {
    final gateway = _Assets();
    await mount(tester, gateway);
    expect(find.text('我的轻柔声音'), findsOneWidget);
    expect(find.byType(AssistantAvatar), findsNothing);
    expect(find.byType(VoiceCover), findsOneWidget);
    await tester.tap(find.text('系统音色'));
    await tester.pumpAndSettle();
    expect(find.text('独立男声'), findsOneWidget);
    await tester.tap(find.text('社区音色'));
    await tester.pumpAndSettle();
    expect(find.text('社区低沉声音'), findsOneWidget);
    expect(gateway.roleLoads, 0);
  });
  testWidgets(
      'draft voice creation persists independently before any role exists',
      (tester) async {
    final gateway = _Assets();
    await mount(tester, gateway);
    await tester.tap(find.byKey(const ValueKey('create-voice')));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceEditorPage), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('voice-name')), '独立保存的声音');
    await tester.tap(find.text('保存音色'));
    await tester.pumpAndSettle();
    expect(gateway.created, 1);
    expect(gateway.roleLoads, 0);
    expect(find.text('独立保存的声音'), findsWidgets);
    final apply =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '给搭子使用'));
    expect(apply.onPressed, isNull);
  });
  testWidgets(
      'choosing a ready asset explicitly applies its id to a selected role',
      (tester) async {
    final gateway = _Assets();
    await mount(tester, gateway);
    await tester.tap(find.byKey(const ValueKey('voice-asset-asset-mine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('给搭子使用'));
    await tester.pumpAndSettle();
    expect(gateway.roleLoads, 1);
    await tester.tap(find.text('测试搭子'));
    await tester.pumpAndSettle();
    expect(gateway.assignments, [('role-A', 'asset-mine')]);
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets('late preview results cannot play after the library is closed',
      (tester) async {
    final gateway = _Assets();
    await mount(tester, gateway);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(gateway.previews, ['asset-mine']);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    gateway.preview.complete(Uint8List.fromList([1, 2]));
    await tester.pumpAndSettle();
    expect(played, contains('stopPreviewAudio'));
    expect(played, isNot(contains('playPreviewAudio')));
  });
  testWidgets('asset library fits narrow screens with larger text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _Assets();
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: VoiceLibraryPage(gateway: gateway, roles: gateway)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
