import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/roles/presentation/companion_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Roles implements RoleGateway {
  final preview = Completer<Uint8List>();
  final previews = <String>[];
  @override
  Future<List<RoleOption>> listRoles() async => const [
        RoleOption(
            id: 'official', name: '男朋友', nickname: '官方声音', builtin: true),
        RoleOption(id: 'mine', name: '女朋友', nickname: '自己的声音', builtin: false),
        RoleOption(
            id: 'community',
            name: '老师',
            nickname: '社区声音',
            builtin: false,
            identityEditable: false),
        RoleOption(
            id: 'silent',
            name: '同事',
            nickname: '未设声音',
            builtin: false,
            hasVoice: false),
      ];
  @override
  Future<Uint8List> previewRoleVoice(String id) {
    previews.add(id);
    return preview.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('bingo/device_tools'),
            (call) async {
      calls.add(call.method);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), null));
  Future<void> mount(WidgetTester tester, _Roles gateway,
      {Future<void> Function(String)? onRole}) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: CompanionLibraryPage(
            gateway: gateway,
            onRole: onRole ?? (_) async {},
            onCreate: () async {})));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'role management opens the selected role and filters created roles',
      (tester) async {
    final opened = <String>[];
    await mount(tester, _Roles(), onRole: (id) async => opened.add(id));
    await tester.tap(find.text('我创建的'));
    await tester.pumpAndSettle();
    expect(find.text('官方声音'), findsNothing);
    expect(find.text('社区声音'), findsNothing);
    await tester.tap(find.text('自己的声音'));
    await tester.pumpAndSettle();
    expect(opened, ['mine']);
  });
}
