import 'dart:async';
import 'dart:collection';
import 'dart:math';

class BubblePacer {
  BubblePacer(
      {double Function()? random, Duration Function()? elapsedSinceReveal})
      : _random = random ?? Random().nextDouble,
        _elapsedSinceReveal = elapsedSinceReveal;

  final double Function() _random;
  final Duration Function()? _elapsedSinceReveal;
  final Queue<({String content, void Function() reveal, Future<void>? played})>
      _pending = Queue();
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  Completer<void>? _drained;
  bool _hasShown = false;
  bool _holding = false;
  int _generation = 0;

  bool get isPending => _pending.isNotEmpty;

  static Duration interval(String content, double random) {
    final seconds = ((0.6 + content.runes.length * 0.04) *
            (0.85 + random.clamp(0.0, 1.0) * 0.3))
        .clamp(1.0, 3.0);
    return Duration(microseconds: (seconds * 1000000).round());
  }

  void enqueue(String content, void Function() reveal, {Future<void>? played}) {
    _pending.add((content: content, reveal: reveal, played: played));
    _drained ??= Completer<void>();
    if (_timer == null && !_holding) _schedule();
  }

  void _schedule() {
    if (_holding) return;
    if (_pending.isEmpty) {
      _drained?.complete();
      _drained = null;
      return;
    }
    final delay = _hasShown
        ? interval(_pending.first.content, _random()) -
            (_elapsedSinceReveal?.call() ?? _elapsed.elapsed)
        : Duration.zero;
    if (delay <= Duration.zero) {
      _reveal();
    } else {
      _timer = Timer(delay, _reveal);
    }
  }

  void _reveal() {
    _timer = null;
    final entry = _pending.removeFirst();
    _hasShown = true;
    _elapsed
      ..reset()
      ..start();
    final played = entry.played;
    _holding = played != null;
    final generation = _generation;
    entry.reveal();
    if (played == null) {
      _schedule();
    } else {
      unawaited(played.then((_) {
        if (generation != _generation) return;
        _holding = false;
        _schedule();
      }));
    }
  }

  Future<void> get drained => _drained?.future ?? Future.value();

  void reset() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _hasShown = false;
    _holding = false;
    _elapsed
      ..stop()
      ..reset();
    _drained?.complete();
    _drained = null;
  }
}
