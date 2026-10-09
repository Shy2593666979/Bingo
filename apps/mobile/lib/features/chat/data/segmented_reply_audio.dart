import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:bingo/features/chat/data/reply_audio_player.dart';

class SegmentedReplyAudio {
  SegmentedReplyAudio(this.player, {required this.onError, this.onStarted});

  final ReplyAudioPlayer player;
  final void Function() onError;
  final void Function()? onStarted;
  final Map<int, _AudioSegment> _segments = {};
  int _generation = 0;
  int _bufferedBytes = 0;
  int? _active;

  _AudioSegment _segment(int index) =>
      _segments.putIfAbsent(index, _AudioSegment.new);

  Future<void> played(int index) => _segment(index).played.future;

  void reveal(int index) {
    _active = index;
    _flush(index);
  }

  void add(int index, Uint8List bytes) {
    if (_bufferedBytes + bytes.length > 8 * 1024 * 1024) {
      cancel();
      onError();
      return;
    }
    final segment = _segment(index);
    if (segment.ended || segment.played.isCompleted) return;
    segment.chunks.add(bytes);
    _bufferedBytes += bytes.length;
    _flush(index);
  }

  void end(int index) {
    _segment(index).ended = true;
    _flush(index);
  }

  void finish() {
    for (final index in _segments.keys.toList()) {
      end(index);
    }
  }

  void _flush(int index) {
    final segment = _segment(index);
    if (_active != index || segment.draining || segment.played.isCompleted) {
      return;
    }
    segment.draining = true;
    final generation = _generation;
    unawaited(() async {
      try {
        while (segment.chunks.isNotEmpty) {
          final bytes = segment.chunks.removeFirst();
          _bufferedBytes -= bytes.length;
          await player.add(bytes);
          if (generation != _generation) return;
          onStarted?.call();
        }
        if (segment.ended) {
          await player.finish();
          if (generation != _generation) return;
          segment.played.complete();
        }
      } catch (_) {
        if (generation != _generation) return;
        cancel();
        onError();
      } finally {
        segment.draining = false;
      }
    }());
  }

  void cancel() {
    _generation++;
    for (final segment in _segments.values) {
      if (!segment.played.isCompleted) segment.played.complete();
    }
    _segments.clear();
    _bufferedBytes = 0;
    _active = null;
  }
}

class _AudioSegment {
  final Queue<Uint8List> chunks = Queue();
  final Completer<void> played = Completer<void>();
  bool ended = false;
  bool draining = false;
}
