import 'dart:async';
import 'package:bingo/features/chat/data/reply_audio_player.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/group_chat/presentation/group_reply_presenter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

GroupChatMessage row(int seq,
        {String status = 'completed',
        String type = 'assistant',
        String run = 'run',
        String? client,
        String? id,
        String? content}) =>
    GroupChatMessage.fromJson({
      'id': id ?? 'm$seq',
      'seq': seq,
      'run_id': run,
      'sender_type': type,
      'sender_role_id': 'role$seq',
      'sender_name': '搭子$seq',
      'content': content ?? '回应$seq',
      'status': status,
      'created_at': '2026-11-02T10:00:00Z',
      'client_message_id': client,
    });

class Audio extends ReplyAudioPlayer {
  final heard = <int>[];
  Completer<void>? finishGate;
  int stops = 0;
  @override
  Future<void> add(Uint8List bytes) async {
    heard.add(bytes.first);
  }

  @override
  Future<void> finish() async {
    await finishGate?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (finishGate != null && !finishGate!.isCompleted) finishGate!.complete();
  }
}

class Gateway implements GroupGateway, GroupSpeechGateway {
  final played = <String>[];
  String? fail;
  int stops = 0;
  @override
  Stream<Uint8List> groupMessageSpeech(
      String groupId, String messageId) async* {
    played.add(messageId);
    if (fail == messageId) throw StateError('Speech unavailable');
    yield Uint8List.fromList([int.parse(messageId.substring(1))]);
  }

  @override
  void stopGroupSpeech() {
    stops++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupReplyPresenter presenter(Gateway gateway, Audio audio,
        {void Function()? onError, bool fast = true}) =>
    GroupReplyPresenter(
        gateway: gateway,
        groupId: 'g',
        player: audio,
        onError: onError ?? () {},
        silentInterval: fast ? Duration.zero : const Duration(seconds: 3),
        minimumInterval:
            fast ? Duration.zero : const Duration(milliseconds: 1500),
        afterSpeech: fast ? Duration.zero : const Duration(milliseconds: 700));

Future<void> flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  testWidgets('unread generated welcomes queue even when ready before opening',
      (tester) async {
    final gateway = Gateway(),
        audio = Audio(),
        view = presenter(gateway, audio, fast: false);
    final rows = [row(1, run: 'welcome-a'), row(2, run: 'welcome-b')];
    view.update(rows, sound: false, welcomeReadThrough: 0);
    await tester.pump();
    expect(view.messages.length, 1);
    expect(view.readThrough, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(view.messages.length, 2);
    view.dispose();
    final history = presenter(gateway, audio);
    history.update(rows, sound: true, welcomeReadThrough: 2);
    expect(history.messages.length, 2);
    expect(gateway.played, isEmpty);
    history.dispose();
  });
  testWidgets(
      'turning sound off keeps queued bubbles paced and never replays the current one',
      (tester) async {
    final gateway = Gateway(),
        audio = Audio(),
        view = presenter(gateway, audio, fast: false);
    view.update([], sound: true);
    audio.finishGate = Completer<void>();
    view.update([row(1), row(2)], sound: true);
    await tester.pump();
    expect(gateway.played, ['m1']);
    view.update([row(1), row(2)], sound: false);
    await tester.pump();
    expect(view.messages.length, 1);
    await tester.pump(const Duration(milliseconds: 2800));
    expect(view.messages.length, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(view.messages.length, 2);
    expect(gateway.played, ['m1']);
    view.update([row(1), row(2)], sound: true);
    await tester.pump();
    expect(gateway.played, ['m1']);
    view.dispose();
  });
  test('older history backfill is immediate and silent', () async {
    final gateway = Gateway(),
        audio = Audio(),
        view = presenter(gateway, audio);
    view.update([row(5), row(6)], sound: true);
    view.update([row(3), row(4), row(5), row(6), row(7)], sound: true);
    await flush();
    expect(view.messages.length, 5);
    expect(gateway.played, ['m7']);
    view.dispose();
  });
  test('history is immediate and later bubbles wait for actual audio drain',
      () async {
    final gateway = Gateway(), audio = Audio();
    final view = presenter(gateway, audio);
    view.update([row(1), row(2)], sound: true);
    expect(view.messages.map((m) => m.id), ['m1', 'm2']);
    expect(gateway.played, isEmpty);
    audio.finishGate = Completer<void>();
    view.update([row(1), row(2), row(3), row(4)], sound: true);
    await flush();
    expect(view.messages.map((m) => m.id), ['m1', 'm2', 'm3']);
    expect(view.readThrough, 3);
    expect(gateway.played, ['m3']);
    await flush();
    expect(view.messages.last.id, 'm3');
    audio.finishGate!.complete();
    await flush();
    expect(view.messages.last.id, 'm4');
    expect(gateway.played, ['m3', 'm4']);
    view.dispose();
  });
  test('streaming current bubble updates but next completed role stays hidden',
      () async {
    final gateway = Gateway(),
        audio = Audio(),
        view = presenter(gateway, audio);
    view.update([], sound: true);
    view.update([row(1, status: 'streaming', content: ''), row(2)],
        sound: true);
    await flush();
    expect(view.messages, isEmpty);
    view.update([row(1, status: 'streaming'), row(2)], sound: true);
    await flush();
    expect(view.messages.single.id, 'm1');
    expect(gateway.played, isEmpty);
    audio.finishGate = Completer<void>();
    view.update([row(1), row(2)], sound: true);
    await flush();
    expect(gateway.played, ['m1']);
    expect(view.messages.length, 1);
    audio.finishGate!.complete();
    await flush();
    expect(view.messages.length, 2);
    view.dispose();
  });
  testWidgets(
      'silent mode shows one bubble then waits three seconds without speech',
      (tester) async {
    final gateway = Gateway(),
        audio = Audio(),
        view = presenter(gateway, audio, fast: false);
    view.update([], sound: false);
    view.update([row(1), row(2), row(3)], sound: false);
    await tester.pump();
    expect(view.messages.map((m) => m.id), ['m1']);
    await tester.pump(const Duration(milliseconds: 2800));
    expect(view.messages.length, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(view.messages.map((m) => m.id), ['m1', 'm2']);
    expect(gateway.played, isEmpty);
    view.dispose();
  });
  testWidgets(
      'a human send interrupts queued old replies and appears immediately',
      (tester) async {
    final gateway = Gateway(),
        audio = Audio(),
        view = presenter(gateway, audio, fast: false);
    view.update([], sound: false);
    view.update([row(1), row(2)], sound: false);
    await tester.pump();
    final human = row(4, type: 'user', run: 'new', client: 'send-1');
    view.interrupt(runId: 'run');
    view.update([row(1), row(2), human], sound: false);
    expect(view.messages.last.id, 'm4');
    view.update([row(1), row(2), row(3), human], sound: false);
    await tester.pump(const Duration(seconds: 10));
    expect(view.messages.map((m) => m.id), ['m1', 'm4']);
    expect(view.readThrough, 1);
    view.dispose();
  });
  test(
      'optimistic acknowledgement and final history do not cancel the live run',
      () async {
    final gateway = Gateway(),
        audio = Audio(),
        view = presenter(gateway, audio);
    view.update([], sound: true);
    view.update([
      row(1,
          type: 'user',
          id: 'local-send-1',
          run: 'local-send-1',
          client: 'send-1')
    ], sound: true);
    audio.finishGate = Completer<void>();
    view.update([
      row(1, type: 'user', run: 'new', client: 'send-1'),
      row(2, run: 'new'),
      row(3, run: 'new')
    ], sound: true);
    await flush();
    expect(gateway.played, ['m2']);
    view.update([
      row(1, type: 'user', run: 'new'),
      row(2, run: 'new'),
      row(3, run: 'new')
    ], sound: true);
    audio.finishGate!.complete();
    await flush();
    expect(gateway.played, ['m2', 'm3']);
    expect(view.messages.length, 3);
    view.dispose();
  });
  test('speech failure falls back to paced text and does not deadlock',
      () async {
    final gateway = Gateway()..fail = 'm1', audio = Audio();
    var errors = 0;
    final view = presenter(gateway, audio, onError: () => errors++);
    view.update([], sound: true);
    view.update([row(1), row(2)], sound: true);
    await flush();
    expect(errors, 1);
    expect(view.messages.length, 2);
    expect(gateway.played, ['m1', 'm2']);
    view.dispose();
  });
  test('background resumes as history without replaying old audio', () async {
    final gateway = Gateway(),
        audio = Audio(),
        view = presenter(gateway, audio);
    view.update([row(1)], sound: true);
    view.suspend(historyOnResume: true);
    view.update([row(1), row(2)], sound: true, enabled: false);
    view.update([row(1), row(2), row(3)], sound: true);
    await flush();
    expect(view.messages.length, 3);
    expect(gateway.played, isEmpty);
    view.update([row(1), row(2), row(3), row(4)], sound: true);
    await flush();
    expect(gateway.played, ['m4']);
    view.dispose();
  });
}
