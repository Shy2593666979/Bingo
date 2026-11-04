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
  testWidgets(
      'discussion controls and playback acknowledgements use server state',
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
    await tester.tap(find.text('让大家聊聊'));
    await tester.pump();
    expect(gateway.socket.commands.last['type'], 'resume_discussion');
    event({
      'type': 'discussion_state',
      'enabled': true,
      'phase': 'discussing',
      'max_silent_turns': 50,
      'generation': 0
    });
    await tester.pump();
    expect(find.text('最多50次'), findsOneWidget);
    await tester.tap(find.text('让大家先停一下'));
    expect(gateway.socket.commands.last['type'], 'pause_discussion');
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
