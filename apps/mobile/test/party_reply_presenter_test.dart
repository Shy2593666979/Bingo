import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bingo/features/chat/data/reply_audio_player.dart';
import 'package:bingo/features/entertainment/data/party_game_gateway.dart';
import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/presentation/party_reply_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlayer extends ReplyAudioPlayer {
  final List<int> playedBytes = [];
  Completer<void>? finishGate;
  int finishCount = 0;
  int stopCount = 0;

  @override
  Future<void> add(Uint8List bytes) async {
    playedBytes.add(bytes.length);
  }

  @override
  Future<void> finish() async {
    finishCount++;
    final gate = finishGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

class _FakeSpeechGateway implements PartyGameGateway, PartySpeechGateway {
  final List<String> requestedIds = [];
  final Map<String, StreamController<Uint8List>> controllers = {};
  int stopCalls = 0;

  StreamController<Uint8List> controllerFor(String id) =>
      controllers.putIfAbsent(id, () => StreamController<Uint8List>());

  @override
  Stream<Uint8List> partyMessageSpeech(String gameId, String messageId) {
    requestedIds.add(messageId);
    return controllerFor(messageId).stream;
  }

  @override
  void stopPartySpeech() {
    stopCalls++;
  }

  @override
  Future<Map<String, dynamic>> createPartyGame(GameSetup setup) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> getPartyGame(String id) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> listPartyGames() =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> partyGameAction(
          String id, String type, String value, int revision, String commandId,
          {String stage = ''}) =>
      throw UnimplementedError();

  @override
  Future<WebSocket> connectPartyVoice(String id) => throw UnimplementedError();
}

void main() {
  test('system messages wait behind queued AI messages in chronological order',
      () async {
    final gateway = _FakeSpeechGateway();
    final player = _FakePlayer();
    final presenter = PartyReplyPresenter(
      gateway: gateway,
      gameId: 'g1',
      onError: () {},
      player: player,
      silentInterval: const Duration(milliseconds: 10),
      afterSpeech: const Duration(milliseconds: 10),
      sameSpeakerAfterSpeech: const Duration(milliseconds: 10),
      systemCascadeDelay: const Duration(milliseconds: 10),
    );
    addTearDown(presenter.dispose);

    // Initial snapshot.
    presenter.update(
      [
        {'id': 'm0', 'speaker': null, 'text': '天亮了。无人出局。'},
      ],
      sound: true,
    );
    expect(presenter.messages.map((m) => m['id']), ['m0']);
    expect(presenter.busy, isFalse);

    // New AI speech arrives together with vote result and winner banner.
    final m1Gate = Completer<void>();
    player.finishGate = m1Gate;
    presenter.update(
      [
        {'id': 'm0', 'speaker': null, 'text': '天亮了。无人出局。'},
        {'id': 'm1', 'speaker': 'p1', 'text': '我觉得 2 号有问题。'},
        {'id': 'm2', 'speaker': null, 'text': '投票结果：我→p2'},
        {'id': 'm3', 'speaker': null, 'text': '好人阵营获胜。'},
      ],
      sound: true,
    );

    // Let m1 start speaking; system cards m2 & m3 must NOT jump ahead.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gateway.controllerFor('m1').add(Uint8List.fromList([1, 2, 3]));
    await gateway.controllerFor('m1').close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(presenter.messages.map((m) => m['id']), ['m0', 'm1']);
    expect(presenter.busy, isTrue);

    // Finish m1 playback -> m2 and m3 appear in exact order afterwards.
    m1Gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(presenter.messages.map((m) => m['id']), ['m0', 'm1', 'm2', 'm3']);
    expect(presenter.busy, isFalse);
  });

  test('prefetches N+1 AI audio while bubble N is playing without duplicate TTS',
      () async {
    final gateway = _FakeSpeechGateway();
    final player = _FakePlayer();
    final presenter = PartyReplyPresenter(
      gateway: gateway,
      gameId: 'g1',
      onError: () {},
      player: player,
      silentInterval: const Duration(milliseconds: 5),
      afterSpeech: const Duration(milliseconds: 5),
      sameSpeakerAfterSpeech: const Duration(milliseconds: 5),
      systemCascadeDelay: const Duration(milliseconds: 5),
    );
    addTearDown(presenter.dispose);

    presenter.update(const [], sound: true);

    final m1Gate = Completer<void>();
    player.finishGate = m1Gate;

    // Two AI messages arrive; m3 arrives too so we also verify prefetch stays at N+1.
    presenter.update(
      [
        {'id': 'm1', 'speaker': 'p1', 'text': '第一句发言'},
        {'id': 'm2', 'speaker': 'p2', 'text': '第二句发言'},
        {'id': 'm3', 'speaker': 'p3', 'text': '第三句发言'},
      ],
      sound: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    // While m1 is active, m2 (N+1) should already be prefetched, and NOT m3 yet.
    expect(gateway.requestedIds, ['m1', 'm2']);

    // Feed audio for both m1 and prefetched m2 while m1 is still finishing.
    gateway.controllerFor('m1').add(Uint8List.fromList([10, 20]));
    await gateway.controllerFor('m1').close();
    gateway.controllerFor('m2').add(Uint8List.fromList([30, 40, 50]));
    await gateway.controllerFor('m2').close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(presenter.messages.map((m) => m['id']), ['m1']);

    // Release m1 -> m2 should consume its prefetched audio without requesting m2 again,
    // and m3 should start prefetching immediately!
    player.finishGate = null;
    m1Gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(gateway.requestedIds, ['m1', 'm2', 'm3']);

    gateway.controllerFor('m3').add(Uint8List.fromList([60]));
    await gateway.controllerFor('m3').close();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(presenter.messages.map((m) => m['id']), ['m1', 'm2', 'm3']);
    expect(gateway.requestedIds, ['m1', 'm2', 'm3']);
    expect(player.finishCount, 3);
    expect(presenter.busy, isFalse);
  });

  test('interrupt cancels prefetch and flushes all pending messages', () async {
    final gateway = _FakeSpeechGateway();
    final player = _FakePlayer();
    final presenter = PartyReplyPresenter(
      gateway: gateway,
      gameId: 'g1',
      onError: () {},
      player: player,
    );
    addTearDown(presenter.dispose);

    presenter.update(const [], sound: true);
    presenter.update(
      [
        {'id': 'm1', 'speaker': 'p1', 'text': '第一句'},
        {'id': 'm2', 'speaker': 'p2', 'text': '第二句'},
        {'id': 'm3', 'speaker': null, 'text': '系统结算'},
      ],
      sound: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gateway.requestedIds, ['m1', 'm2']);

    presenter.interrupt();
    expect(presenter.busy, isFalse);
    expect(presenter.messages.map((m) => m['id']), ['m1', 'm2', 'm3']);
    expect(gateway.stopCalls, greaterThanOrEqualTo(1));
  });
}
