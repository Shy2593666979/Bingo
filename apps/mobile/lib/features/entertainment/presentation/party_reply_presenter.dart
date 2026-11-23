import 'dart:async';
import 'package:bingo/features/chat/data/reply_audio_player.dart';
import 'package:bingo/features/entertainment/data/party_game_gateway.dart';
import 'package:flutter/foundation.dart';

/// Paces newly arriving game messages in strict chronological order,
/// reading AI messages aloud and prefetching the next AI bubble's audio (N+1).
class PartyReplyPresenter extends ChangeNotifier {
  PartyReplyPresenter({
    required this.gateway,
    required this.gameId,
    required this.onError,
    ReplyAudioPlayer? player,
    this.silentInterval = const Duration(milliseconds: 1400),
    this.afterSpeech = const Duration(milliseconds: 600),
    this.sameSpeakerAfterSpeech = const Duration(milliseconds: 280),
    this.systemCascadeDelay = const Duration(milliseconds: 350),
  }) : _player = player ?? ReplyAudioPlayer();

  final PartyGameGateway gateway;
  final String gameId;
  final VoidCallback onError;
  final ReplyAudioPlayer _player;
  final Duration silentInterval,
      afterSpeech,
      sameSpeakerAfterSpeech,
      systemCascadeDelay;

  List<Map<String, dynamic>> _source = [];
  final _visible = <String>{}, _known = <String>{}, _pending = <String>[];
  final _sinceReveal = Stopwatch(), _sinceSpeech = Stopwatch();
  bool _initialized = false,
      _enabled = true,
      _sound = true,
      _running = false,
      _lastSpoken = false,
      _disposed = false;
  int _generation = 0;
  String? _speakingId;
  String? _loadingSpeechId;
  String? _lastSpeaker;
  Timer? _timer;
  Completer<void>? _delayDone;
  Future<void> _stopping = Future.value();
  _PrefetchedAudio? _prefetched;
  _PrefetchedAudio? _activePrefetch;

  String? get speakingId => _speakingId;
  String? get loadingSpeechId => _loadingSpeechId;
  bool get busy => _running || _pending.isNotEmpty;

  String? get activeSpeakerId {
    final activeId = _speakingId ?? _loadingSpeechId;
    if (activeId == null) return null;
    final row = _row(activeId);
    return row?['speaker'] as String?;
  }

  List<Map<String, dynamic>> get messages =>
      _source.where((m) => _visible.contains(m['id'] as String)).toList();

  Map<String, dynamic>? _row(String id) {
    for (final item in _source) {
      if (item['id'] == id) return item;
    }
    return null;
  }

  bool _isAiRow(Map<String, dynamic>? row) {
    if (row == null) return false;
    final speaker = row['speaker'] as String?;
    return speaker != null &&
        speaker != 'self' &&
        (row['text'] as String? ?? '').trim().isNotEmpty;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void update(
    List<Map<String, dynamic>> source, {
    required bool sound,
    bool enabled = true,
  }) {
    if (_disposed) return;
    if (_sound != sound || _enabled != enabled) {
      _cancelWork();
      if (!enabled) {
        for (final id in _pending) {
          _visible.add(id);
        }
        _pending.clear();
      }
    }
    _sound = sound;
    _enabled = enabled;
    _source = List.of(source);
    if (!_initialized) {
      _initialized = true;
      for (final row in source) {
        final id = row['id'] as String;
        _known.add(id);
        _visible.add(id);
      }
      _notify();
      return;
    }
    for (final row in source) {
      final id = row['id'] as String;
      if (!_known.add(id)) continue;
      final speaker = row['speaker'] as String?;
      final isAi = speaker != null && speaker != 'self';
      final isSystem = speaker == null;
      // Keep strict chronological order: system events (vote results, eliminations,
      // winner banners) wait behind any unplayed AI bubbles instead of jumping ahead.
      if (_enabled &&
          (isAi || (isSystem && (_running || _pending.isNotEmpty)))) {
        _pending.add(id);
      } else {
        _visible.add(id);
      }
    }
    _pending.removeWhere((id) => !_source.any((row) => row['id'] == id));
    if (_prefetched != null && !_pending.contains(_prefetched!.messageId)) {
      _prefetched!.cancel();
      _prefetched = null;
    }
    _notify();
    _start();
    _maybePrefetchNext();
  }

  void _start() {
    if (_running || !_enabled || _disposed || _pending.isEmpty) return;
    _running = true;
    unawaited(_drain(_generation));
  }

  /// Prefetches TTS audio for at most one upcoming AI message (N+1) in _pending.
  void _maybePrefetchNext() {
    if (_disposed || !_enabled || !_sound || !_running) return;
    if (gateway is! PartySpeechGateway) return;
    String? nextAiId;
    for (final id in _pending) {
      if (_isAiRow(_row(id))) {
        nextAiId = id;
        break;
      }
    }
    if (nextAiId == null) return;
    if (_prefetched?.messageId == nextAiId) return;
    _prefetched?.cancel();
    final speech = gateway as PartySpeechGateway;
    _prefetched =
        _PrefetchedAudio(nextAiId, speech.partyMessageSpeech(gameId, nextAiId));
  }

  bool _valid(int generation) =>
      !_disposed && _enabled && generation == _generation;

  Duration _remainingFor(String? nextSpeaker) {
    if (!_sinceReveal.isRunning) return Duration.zero;
    if (nextSpeaker == null) {
      if (_sound && _lastSpoken) {
        final breath = afterSpeech - _sinceSpeech.elapsed;
        return breath > Duration.zero ? breath : Duration.zero;
      }
      final target = _lastSpeaker == null
          ? systemCascadeDelay
          : const Duration(milliseconds: 500);
      final natural = target - _sinceReveal.elapsed;
      return natural > Duration.zero ? natural : Duration.zero;
    }
    final same = nextSpeaker == _lastSpeaker;
    if (!_sound || !_lastSpoken) {
      final target = same
          ? const Duration(milliseconds: 800)
          : silentInterval;
      final natural = target - _sinceReveal.elapsed;
      return natural > Duration.zero ? natural : Duration.zero;
    }
    final target = same ? sameSpeakerAfterSpeech : afterSpeech;
    final breath = target - _sinceSpeech.elapsed;
    return breath > Duration.zero ? breath : Duration.zero;
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

  Future<void> _drain(int generation) async {
    try {
      await _stopping;
      while (_valid(generation) && _pending.isNotEmpty) {
        final id = _pending.first;
        final row = _row(id);
        if (row == null || (row['text'] as String? ?? '').trim().isEmpty) {
          _pending.removeAt(0);
          continue;
        }
        final speaker = row['speaker'] as String?;
        final isAi = speaker != null && speaker != 'self';
        // Give the next AI message a head start during the inter-bubble breath.
        _maybePrefetchNext();
        await _delay(_remainingFor(speaker));
        if (!_valid(generation)) return;
        _pending.removeAt(0);
        _visible.add(id);
        _lastSpeaker = speaker;
        _sinceReveal
          ..reset()
          ..start();
        _lastSpoken = false;
        _notify();

        if (!isAi) {
          continue;
        }

        if (_sound && gateway is PartySpeechGateway) {
          final speech = gateway as PartySpeechGateway;
          _PrefetchedAudio? pre;
          if (_prefetched?.messageId == id) {
            pre = _prefetched;
            _prefetched = null;
          }
          _activePrefetch = pre;
          // Immediately prefetch N+1 while bubble N plays aloud.
          _maybePrefetchNext();

          _loadingSpeechId = id;
          _notify();
          try {
            var heard = false;
            final audioStream = pre != null
                ? pre.consume()
                : speech.partyMessageSpeech(gameId, id);
            await for (final bytes
                in audioStream.timeout(const Duration(seconds: 45))) {
              if (!_valid(generation)) return;
              if (bytes.isEmpty) continue;
              heard = true;
              if (_speakingId != id) {
                _loadingSpeechId = null;
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
            pre?.cancel();
            if (identical(_activePrefetch, pre)) _activePrefetch = null;
            if (_valid(generation)) {
              _loadingSpeechId = null;
              _speakingId = null;
              _notify();
            }
          }
        }
      }
    } finally {
      if (generation == _generation) {
        _running = false;
        _loadingSpeechId = null;
        _speakingId = null;
        _notify();
      }
    }
  }

  void _cancelWork() {
    _generation++;
    _running = false;
    _loadingSpeechId = null;
    _speakingId = null;
    _timer?.cancel();
    _timer = null;
    final delay = _delayDone;
    _delayDone = null;
    if (delay != null && !delay.isCompleted) delay.complete();
    _prefetched?.cancel();
    _prefetched = null;
    _activePrefetch?.cancel();
    _activePrefetch = null;
    if (gateway case final PartySpeechGateway speech) {
      speech.stopPartySpeech();
    }
    _stopping = _player.stop();
  }

  /// Stops current playback and flushes any buffered messages immediately.
  void interrupt() {
    for (final id in _pending) {
      _visible.add(id);
    }
    _pending.clear();
    _cancelWork();
    _notify();
  }

  void suspend() {
    _enabled = false;
    _cancelWork();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelWork();
    super.dispose();
  }
}

class _PrefetchedAudio {
  _PrefetchedAudio(this.messageId, Stream<Uint8List> stream) {
    _sub = stream.listen(
      (chunk) {
        if (chunk.isEmpty) return;
        _chunks.add(chunk);
        _wake();
      },
      onError: (Object err, StackTrace st) {
        _error = err;
        _done = true;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  final String messageId;
  final List<Uint8List> _chunks = [];
  StreamSubscription<Uint8List>? _sub;
  Completer<void>? _waiter;
  bool _done = false;
  bool _cancelled = false;
  Object? _error;

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  Stream<Uint8List> consume() async* {
    var index = 0;
    while (true) {
      while (index < _chunks.length) {
        yield _chunks[index++];
      }
      if (_cancelled) return;
      if (_done) {
        if (_error != null) throw _error!;
        return;
      }
      final waiter = Completer<void>();
      _waiter = waiter;
      await waiter.future;
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _done = true;
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
    _wake();
  }
}
