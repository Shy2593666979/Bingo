import 'dart:async';

import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/reply_audio_player.dart';
import 'package:flutter/foundation.dart';

class _NarrativePart {
  _NarrativePart(this.runId, this.closing);
  final String runId;
  final bool closing;
  final chunks = <Uint8List>[];
  int bytes = 0;
  String text = '';
  bool ready = false;
  double get seconds => bytes / 48000;

  Uint8List? slice(int offset) {
    for (final chunk in chunks) {
      if (offset < chunk.length) {
        return Uint8List.sublistView(
            chunk, offset, (offset + 9600).clamp(0, chunk.length));
      }
      offset -= chunk.length;
    }
    return null;
  }
}

class SleepSession extends ChangeNotifier {
  SleepSession(
      {required this.gateway,
      required this.conversationId,
      required this.mode,
      required this.minutes,
      required this.onEnded,
      ReplyAudioPlayer? player,
      DateTime Function()? now})
      : _player = player ?? ReplyAudioPlayer(),
        _now = now ?? DateTime.now;

  final MomentGateway gateway;
  final String conversationId;
  final String mode;
  final int minutes;
  final Future<void> Function(bool automatic, int seconds) onEnded;
  final ReplyAudioPlayer _player;
  final DateTime Function() _now;
  final _parts = <_NarrativePart>[];
  final _runs = <String>{};
  final _history = <String>[];
  Timer? _timer;
  DateTime? _startedAt;
  DateTime? _pausedAt;
  Duration _pausedDuration = Duration.zero;
  int _generation = 0;
  int _sentBytes = 0;
  double _completedSeconds = 0;
  double _rate = 3.7;
  bool _pumping = false;
  bool active = false;
  bool paused = false;
  bool started = false;
  bool _prefetchFailed = false;
  int _lastNotifiedSecond = -1;
  String? error;
  String get text => _parts.isEmpty ? '' : _parts.first.text;
  int get elapsedSeconds => _startedAt == null
      ? 0
      : ((_pausedAt ?? _now()).difference(_startedAt!) - _pausedDuration)
          .inSeconds
          .clamp(0, minutes * 60);
  int get remainingSeconds => minutes * 60 - elapsedSeconds;
  bool get loading => active && !started;

  void start() {
    if (active || started) return;
    active = true;
    if (mode == 'quiet') {
      started = true;
      _startedAt = _now();
    } else {
      _generate(300.clamp(20, minutes * 60), minutes * 60 <= 300);
    }
    _timer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => unawaited(_tick()));
    notifyListeners();
  }

  void _generate(int seconds, bool closing) {
    final generation = _generation;
    final part = _NarrativePart(
        'sleep-${_now().microsecondsSinceEpoch}-${_runs.length}-${_history.length}',
        closing);
    _parts.add(part);
    _runs.add(part.runId);
    unawaited(() async {
      try {
        await for (final event in gateway.generateMoment(
            conversationId: conversationId,
            runId: part.runId,
            mode: mode,
            previous: _history.join('\n'),
            seconds: seconds,
            charactersPerSecond: _rate,
            closing: closing)) {
          if (generation != _generation) return;
          if (event is ChatAudio) {
            if (part.bytes + event.bytes.length > 24 * 1024 * 1024) {
              throw StateError('声音缓冲过长');
            }
            part.chunks.add(event.bytes);
            part.bytes += event.bytes.length;
          } else if (event is ChatSegment) {
            part.text = event.content;
          } else if (event is ChatAudioError) {
            throw StateError(event.message);
          }
        }
        if (generation != _generation) return;
        if (part.bytes == 0) throw StateError('没有收到陪伴声音');
        part.ready = true;
        _history.add(part.text);
        _rate = (part.text.replaceAll(RegExp(r'\s'), '').length / part.seconds)
            .clamp(2, 6);
        _prefetch();
      } catch (_) {
        if (generation != _generation) return;
        if (_parts.isNotEmpty && _parts.first != part) {
          _parts.remove(part);
          _prefetchFailed = true;
          error = '下一段未准备好，会讲完当前段再结束';
        } else {
          error = '陪伴连接中断，可以结束后重新尝试';
          await pause();
        }
      } finally {
        _runs.remove(part.runId);
        if (generation == _generation) notifyListeners();
      }
    }());
  }

  void _prefetch() {
    if (!active || _prefetchFailed || _parts.isEmpty || _parts.length >= 2) {
      return;
    }
    final current = _parts.first;
    if (!current.ready || current.closing) return;
    final afterCurrent = minutes * 60 - _completedSeconds - current.seconds;
    if (afterCurrent <= 0) return;
    final target = afterCurrent.ceil().clamp(20, 300);
    _generate(target, afterCurrent <= 330);
  }

  Future<void> _tick() async {
    if (!active || paused || _pumping) return;
    if (started && remainingSeconds == 0) {
      await end(automatic: true);
      return;
    }
    if (mode == 'quiet') {
      notifyListeners();
      return;
    }
    if (_parts.isEmpty) return;
    _pumping = true;
    final generation = _generation;
    try {
      final part = _parts.first;
      final played = elapsedSeconds - _completedSeconds;
      if (part.ready && _sentBytes >= part.bytes && played >= part.seconds) {
        _completedSeconds += part.seconds;
        _parts.removeAt(0);
        _sentBytes = 0;
        if (_prefetchFailed && _parts.isEmpty) {
          await end();
        } else if (part.closing || remainingSeconds <= 1) {
          await end(automatic: true);
        } else {
          _prefetch();
        }
        return;
      }
      if (_sentBytes / 48000 - played > 2) return;
      final chunk = part.slice(_sentBytes);
      if (chunk != null) {
        if (!started) {
          started = true;
          _startedAt = _now();
          _pausedDuration = Duration.zero;
        }
        await _player.add(chunk);
        if (generation == _generation) _sentBytes += chunk.length;
      }
    } catch (_) {
      error = '声音播放暂不可用，可以结束后重试';
      await pause();
    } finally {
      _pumping = false;
      if (generation == _generation && elapsedSeconds != _lastNotifiedSecond) {
        _lastNotifiedSecond = elapsedSeconds;
        notifyListeners();
      }
    }
  }

  Future<void> pause() async {
    if (!active || paused) return;
    paused = true;
    _pausedAt = _now();
    await _player.stop();
    if (_parts.isNotEmpty) {
      final playedBytes =
          ((elapsedSeconds - _completedSeconds).clamp(0, double.infinity) *
                  48000)
              .floor();
      _sentBytes = (playedBytes ~/ 2 * 2).clamp(0, _parts.first.bytes);
    }
    notifyListeners();
  }

  void resume() {
    if (!active || !paused || (error != null && !_prefetchFailed)) return;
    _pausedDuration += _now().difference(_pausedAt!);
    _pausedAt = null;
    paused = false;
    notifyListeners();
  }

  Future<void> end({bool automatic = false}) async {
    if (!active) return;
    final elapsed = elapsedSeconds;
    final hadStarted = started;
    active = false;
    _generation++;
    _timer?.cancel();
    await _player.stop();
    for (final run in List<String>.of(_runs)) {
      unawaited(gateway.cancelMoment(run));
    }
    _parts.clear();
    _history.clear();
    notifyListeners();
    if (hadStarted) {
      try {
        await onEnded(automatic, elapsed);
      } catch (_) {
        error = '结束记录尚未发送，请返回时重试';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    active = false;
    _generation++;
    _timer?.cancel();
    unawaited(_player.stop());
    for (final run in List<String>.of(_runs)) {
      unawaited(gateway.cancelMoment(run));
    }
    super.dispose();
  }
}
