import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bingo/features/chat/data/reply_audio_player.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';

/// Keeps canonical messages intact while pacing only newly arriving AI bubbles.
class GroupReplyPresenter extends ChangeNotifier {
  GroupReplyPresenter(
      {required this.gateway,
      required this.groupId,
      required this.onError,
      ReplyAudioPlayer? player,
      this.silentInterval = const Duration(seconds: 3),
      this.minimumInterval = const Duration(milliseconds: 1500),
      this.afterSpeech = const Duration(milliseconds: 700)})
      : _player = player ?? ReplyAudioPlayer();
  final GroupGateway gateway;
  final String groupId;
  final VoidCallback onError;
  final ReplyAudioPlayer _player;
  final Duration silentInterval, minimumInterval, afterSpeech;
  List<GroupChatMessage> _source = [];
  final _visible = <String>{}, _known = <String>{}, _pending = <String>{};
  final _suppressedRuns = <String>{},
      _liveRuns = <String>{},
      _users = <String>{};
  final _sinceReveal = Stopwatch(), _sinceSpeech = Stopwatch();
  bool _initialized = false, _enabled = true, _sound = true, _running = false;
  bool _lastSpoken = false, _disposed = false;
  bool _historyOnResume = false;
  int _historyCeiling = 0, _generation = 0;
  String? get speakingId => _speakingId;
  String? _speakingId;
  Timer? _timer;
  Completer<void>? _delayDone, _changed;
  Future<void> _stopping = Future.value();
  Future<void> _task = Future.value();
  Future<void> get idle => _task;
  bool get busy => _running || _pending.isNotEmpty;
  List<GroupChatMessage> get messages =>
      _source.where((m) => _visible.contains(m.id)).toList();
  int? get readThrough {
    int? seq;
    final rows = _source.where((m) => !m.local).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    for (final row in rows) {
      if (!_visible.contains(row.id)) break;
      seq = row.seq;
    }
    return seq;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _wake() {
    final waiter = _changed;
    _changed = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void update(List<GroupChatMessage> source,
      {required bool sound, bool enabled = true, int? welcomeReadThrough}) {
    if (_disposed) return;
    if (_historyOnResume && enabled) {
      _initialized = false;
      _historyOnResume = false;
    }
    if (_sound != sound || _enabled != enabled) _cancelWork();
    _sound = sound;
    _enabled = enabled;
    _source = List.of(source);
    if (!_initialized) {
      _initialized = true;
      _historyCeiling = 0;
      _visible.clear();
      _known.clear();
      _pending.clear();
      _users.clear();
      _suppressedRuns.clear();
      _liveRuns.clear();
      _sinceReveal.stop();
      _sinceReveal.reset();
      _lastSpoken = false;
      for (final row in source) {
        if (!row.local && row.seq > _historyCeiling) _historyCeiling = row.seq;
        _known.add(row.id);
        if (row.type == 'user') {
          _users.add(row.runId);
          if (row.clientMessageId != null) _users.add(row.clientMessageId!);
        }
        if (row.type == 'assistant' &&
            (row.status == 'streaming' ||
                (welcomeReadThrough != null &&
                    row.runId.startsWith('welcome-') &&
                    row.seq > welcomeReadThrough))) {
          _pending.add(row.id);
          _liveRuns.add(row.runId);
        } else {
          _visible.add(row.id);
        }
      }
    } else {
      final newUsers = source
          .where((row) =>
              row.type == 'user' &&
              !_known.contains(row.id) &&
              !_users.contains(row.runId) &&
              !_users.contains(row.clientMessageId))
          .toList();
      if (newUsers.isNotEmpty) interrupt();
      for (final row in source) {
        if (row.type == 'user') {
          _users.add(row.runId);
          if (row.clientMessageId != null) _users.add(row.clientMessageId!);
        }
        if (row.type != 'assistant') {
          _visible.add(row.id);
          _known.add(row.id);
          continue;
        }
        if (!_known.add(row.id)) continue;
        if (_suppressedRuns.contains(row.runId)) continue;
        if (row.seq <= _historyCeiling) {
          _visible.add(row.id);
          continue;
        }
        _pending.add(row.id);
        _liveRuns.add(row.runId);
      }
    }
    _pending.removeWhere((id) => !source.any((row) => row.id == id));
    _wake();
    if (_historyOnResume && !enabled) {
      _initialized = false;
    }
    _notify();
    _start();
  }

  void _start() {
    if (_running || !_enabled || _disposed || _pending.isEmpty) return;
    _running = true;
    _task = _drain(_generation);
  }

  bool _valid(int generation) =>
      !_disposed && _enabled && generation == _generation;
  GroupChatMessage? _row(String id) =>
      _source.where((m) => m.id == id).firstOrNull;
  Duration get _remaining {
    if (!_sinceReveal.isRunning) return Duration.zero;
    final natural = silentInterval - _sinceReveal.elapsed;
    if (!_sound || !_lastSpoken) {
      return natural > Duration.zero ? natural : Duration.zero;
    }
    final minimum = minimumInterval - _sinceReveal.elapsed;
    final breath = afterSpeech - _sinceSpeech.elapsed;
    final delay = minimum > breath ? minimum : breath;
    return delay > Duration.zero ? delay : Duration.zero;
  }

  Future<void> _delay(Duration duration) async {
    if (duration <= Duration.zero) return;
    final done = Completer<void>();
    _delayDone = done;
    _timer = Timer(duration, () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    if (identical(_delayDone, done)) {
      _timer = null;
      _delayDone = null;
    }
  }

  Future<void> _waitForUpdate() async {
    final changed = Completer<void>();
    _changed = changed;
    await changed.future;
  }

  Future<void> _drain(int generation) async {
    try {
      await _stopping;
      while (_valid(generation) && _pending.isNotEmpty) {
        final rows = _source.where((m) => _pending.contains(m.id)).toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
        if (rows.isEmpty) break;
        final id = rows.first.id;
        var row = _row(id);
        while (_valid(generation) &&
            row != null &&
            row.status == 'streaming' &&
            row.content.trim().isEmpty) {
          await _waitForUpdate();
          row = _row(id);
        }
        if (!_valid(generation)) return;
        if (row == null || row.content.trim().isEmpty) {
          _pending.remove(id);
          continue;
        }
        await _delay(_remaining);
        if (!_valid(generation)) return;
        _pending.remove(id);
        _visible.add(id);
        _sinceReveal
          ..reset()
          ..start();
        _lastSpoken = false;
        _notify();
        // Let the current bubble stream, but never reveal the next one over it.
        while (_valid(generation) && (row = _row(id))?.status == 'streaming') {
          await _waitForUpdate();
        }
        if (!_valid(generation)) return;
        row = _row(id);
        if (_sound &&
            row?.status == 'completed' &&
            !row!.content.startsWith('[[bingo.sticker.v1]]') &&
            gateway is GroupSpeechGateway) {
          final speech = gateway as GroupSpeechGateway;
          try {
            var heard = false;
            await for (final bytes in speech
                .groupMessageSpeech(groupId, id)
                .timeout(const Duration(seconds: 45))) {
              if (!_valid(generation)) return;
              if (bytes.isEmpty) continue;
              heard = true;
              if (_speakingId != id) {
                _speakingId = id;
                _notify();
              }
              await _player.add(bytes);
            }
            if (!_valid(generation)) return;
            if (!heard) throw StateError('No speech audio');
            await _player.finish();
            if (!_valid(generation)) return;
            _lastSpoken = true;
            _sinceSpeech
              ..reset()
              ..start();
          } catch (_) {
            if (!_valid(generation)) return;
            await _player.stop();
            onError();
          } finally {
            if (_valid(generation)) {
              _speakingId = null;
              _notify();
            }
          }
        }
      }
    } finally {
      if (generation == _generation) {
        _running = false;
        _notify();
      }
    }
  }

  void _cancelWork() {
    _generation++;
    _running = false;
    _speakingId = null;
    _timer?.cancel();
    _timer = null;
    final delay = _delayDone;
    _delayDone = null;
    if (delay != null && !delay.isCompleted) delay.complete();
    _wake();
    if (gateway case final GroupSpeechGateway speech) speech.stopGroupSpeech();
    _stopping = _player.stop();
  }

  /// Stops the old round without exposing or replaying its buffered messages.
  void interrupt({String? runId}) {
    _suppressedRuns.addAll(_liveRuns);
    if (runId != null) _suppressedRuns.add(runId);
    _liveRuns.clear();
    _pending.clear();
    _cancelWork();
    _notify();
  }

  /// Settings preserve the pending display queue; background/re-entry seeds history.
  void suspend({bool historyOnResume = false}) {
    _enabled = false;
    _cancelWork();
    if (historyOnResume) {
      _initialized = false;
      _historyOnResume = true;
    }
  }

  void revealHistory(String id) {
    if (_row(id) != null) {
      _visible.add(id);
      _pending.remove(id);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelWork();
    super.dispose();
  }
}
