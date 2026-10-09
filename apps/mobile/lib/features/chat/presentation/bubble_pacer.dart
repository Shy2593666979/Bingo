import 'dart:async';
import 'dart:collection';
import 'dart:math';

class BubblePacer {
  BubblePacer({double Function()? random})
      : _random = random ?? Random().nextDouble;

  final double Function() _random;
  final Queue<({String content, void Function() reveal})> _pending = Queue();
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  Completer<void>? _drained;
  String? _previous;

  bool get isPending => _pending.isNotEmpty;

  static Duration interval(String content, double random) {
    final seconds = ((0.6 + content.runes.length * 0.04) *
            (0.85 + random.clamp(0.0, 1.0) * 0.3))
        .clamp(0.8, 2.0);
    return Duration(microseconds: (seconds * 1000000).round());
  }

  void enqueue(String content, void Function() reveal) {
    _pending.add((content: content, reveal: reveal));
    _drained ??= Completer<void>();
    if (_timer == null) _schedule();
  }

  void _schedule() {
    if (_pending.isEmpty) {
      _drained?.complete();
      _drained = null;
      return;
    }
    final previous = _previous;
    final delay = previous == null
        ? Duration.zero
        : interval(previous, _random()) - _elapsed.elapsed;
    if (delay <= Duration.zero) {
      _reveal();
    } else {
      _timer = Timer(delay, _reveal);
    }
  }

  void _reveal() {
    _timer = null;
    final entry = _pending.removeFirst();
    _previous = entry.content;
    _elapsed
      ..reset()
      ..start();
    entry.reveal();
    _schedule();
  }

  Future<void> get drained => _drained?.future ?? Future.value();

  void reset() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _previous = null;
    _elapsed
      ..stop()
      ..reset();
    _drained?.complete();
    _drained = null;
  }
}
