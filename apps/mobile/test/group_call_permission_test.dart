import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/group_chat/presentation/group_call_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Socket extends Stream<dynamic> implements WebSocket {
  final controller = StreamController<dynamic>();
  final commands = <Map<String, dynamic>>[];
  @override
  int get readyState => WebSocket.open;
  @override
  void add(dynamic data) {
    if (data is String) commands.add(jsonDecode(data) as Map<String, dynamic>);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    unawaited(controller.close());
  }

  @override
  StreamSubscription<dynamic> listen(void Function(dynamic)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      controller.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gateway implements GroupCallGateway {
  final socket = _Socket();
  @override
  Future<WebSocket> connectGroupCall(
          String groupId, List<String> roleIds) async =>
      socket;
}

void main() {
  testWidgets('game call displays own clues and sends one sealed choice',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _Gateway();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/device_tools'), (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/device_tools'), null));
    final group = ChatGroup.fromJson({
      'id': 'party',
      'name': '搭子推理局',
      'cover': 'coffee',
      'last_activity_at': '2026-11-22T00:00:00Z',
      'members': [
        {'id': 'role-0', 'name': '暖暖', 'role_name': '男朋友', 'active': true},
        {'id': 'role-1', 'name': '甜甜', 'role_name': '女朋友', 'active': true},
      ]
    });
    await tester.pumpWidget(MaterialApp(
        home: GroupCallPage(
            group: group,
            members: group.activeMembers,
            gateway: gateway,
            gameSession: true)));
    await tester.pumpAndSettle();
    gateway.socket.controller.add(jsonEncode({
      'type': 'game_state',
      'state': {
        'mode': 'wolf',
        'phase': 'vote',
        'round': 1,
        'revision': 7,
        'action_stage': '1:vote:false:false',
        'options': {'role-0': '暖暖', 'skip': '弃票'},
        'private': {
          'identity': 'seer',
          'clues': [
            {'day': 1, 'target': 'role-0', 'wolf': false}
          ]
        },
        'messages': [],
      }
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, '暖暖'));
    await tester.pump();
    expect(gateway.socket.commands.where((c) => c['type'] == 'game_choice'),
        hasLength(1));
    expect(gateway.socket.commands.last['value'], 'role-0');
    expect(gateway.socket.commands.last['revision'], 7);
    await tester.tap(find.text('身份与线索'));
    await tester.pumpAndSettle();
    expect(find.text('预言家'), findsOneWidget);
    expect(find.text('第 1 夜：暖暖是好人'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  for (final total in [2, 4, 6, 9]) {
    testWidgets('light call fits $total people and keeps hangup centered',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = _Gateway();
      final methods = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), (call) async {
        methods.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), null));
      final group = ChatGroup.fromJson({
        'id': 'group',
        'name': '一个比较长的群聊名称也应该正常显示',
        'cover': 'coffee',
        'last_activity_at': '2026-11-02T00:00:00Z',
        'members': [
          for (var i = 0; i < total - 1; i++)
            {
              'id': 'role-$i',
              'name': '一个很长的搭子名字$i',
              'role_name': '朋友',
              'active': true
            }
        ],
      });
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!),
          home: GroupCallPage(
              group: group, members: group.activeMembers, gateway: gateway)));
      await tester.pumpAndSettle();
      final left = tester.getCenter(find.byTooltip('静音'));
      final middle = tester.getCenter(find.byTooltip('挂断'));
      final right = tester.getCenter(find.byTooltip('免提'));
      expect(left.dx, lessThan(middle.dx));
      expect(middle.dx, closeTo(160, 1));
      expect(right.dx, greaterThan(middle.dx));
      expect(middle.dy, lessThan(700));
      await tester.tap(find.byTooltip('静音'));
      await tester.pump();
      expect(find.byTooltip('取消静音'), findsOneWidget);
      await tester.tap(find.byTooltip('免提'));
      await tester.pump();
      expect(methods, contains('setCallSpeaker'));
      gateway.socket.controller.add(jsonEncode({
        'type': 'user_transcript',
        'text': '这是一句测试字幕，应在字幕区域完整保留。',
      }));
      await tester.pump();
      expect(find.text('这是一句测试字幕，应在字幕区域完整保留。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('挂断'));
      await tester.pump();
      expect(gateway.socket.commands.where((c) => c['type'] == 'hangup'),
          hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets(
      'natural call needs no activation or limit controls and acknowledges playback',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _Gateway();
    final messenger = tester.binding.defaultBinaryMessenger;
    var outcome = 'timeout';
    messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/device_tools'),
        (call) async =>
            call.method == 'finishCallAudio' ? {'status': outcome} : null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/audio_stream'), (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('bingo/audio_stream'), null);
    });
    final group = ChatGroup.fromJson({
      'id': 'group',
      'name': '测试通话',
      'cover': 'coffee',
      'last_activity_at': '2026-11-02T00:00:00Z',
      'members': [
        {'id': 'one', 'name': '甜甜', 'role_name': '女朋友', 'active': true}
      ],
    });
    await tester.pumpWidget(MaterialApp(
        home: GroupCallPage(
            group: group, members: group.activeMembers, gateway: gateway)));
    await tester.pump();
    void event(Map<String, dynamic> value) =>
        gateway.socket.controller.add(jsonEncode(value));
    event({'type': 'ready'});
    await tester.pump();
    await tester.pump();
    expect(gateway.socket.commands.single['playback_results'], true);
    expect(find.text('让大家聊聊'), findsNothing);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(gateway.socket.commands, hasLength(1));
    event({
      'type': 'discussion_state',
      'enabled': true,
      'phase': 'discussing',
      'max_silent_turns': 30,
      'generation': 0
    });
    await tester.pump();
    expect(find.text('最多30次'), findsNothing);
    expect(find.text('让大家先停一下'), findsNothing);
    event({'type': 'audio_end', 'utterance_id': 'failed-one', 'generation': 0});
    await tester.pump();
    await tester.pump();
    expect(gateway.socket.commands.last, {
      'type': 'played',
      'utterance_id': 'failed-one',
      'generation': 0,
      'status': 'timeout'
    });
    outcome = 'completed';
    event({'type': 'audio_end', 'utterance_id': 'good-one', 'generation': 0});
    await tester.pump();
    await tester.pump();
    expect(gateway.socket.commands.last['status'], 'completed');
    final count = gateway.socket.commands.length;
    event({'type': 'interrupted', 'generation': 1});
    event({'type': 'audio_end', 'utterance_id': 'old-one', 'generation': 0});
    await tester.pump();
    await tester.pump();
    expect(gateway.socket.commands.length, count);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('microphone permission pause does not hang up the call',
      (tester) async {
    final permission = Completer<void>();
    final gateway = _Gateway();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/device_tools'), (call) async {
      if (call.method == 'startCallAudio') await permission.future;
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('bingo/audio_stream'), (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('bingo/device_tools'), null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('bingo/audio_stream'), null);
    });
    final group = ChatGroup.fromJson({
      'id': 'group',
      'name': '测试通话',
      'cover': 'coffee',
      'last_activity_at': '2026-11-02T00:00:00Z',
      'members': [
        {'id': 'one', 'name': '甜甜', 'role_name': '女朋友', 'active': true}
      ]
    });
    await tester.pumpWidget(MaterialApp(
        home: GroupCallPage(
            group: group, members: group.activeMembers, gateway: gateway)));
    await tester.pump();
    gateway.socket.controller.add(jsonEncode({'type': 'ready'}));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(
        gateway.socket.commands.where((c) => c['type'] == 'hangup'), isEmpty);
    expect(find.byType(GroupCallPage), findsOneWidget);
    permission.complete();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(
        gateway.socket.commands.where((c) => c['type'] == 'client_audio_ready'),
        hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
