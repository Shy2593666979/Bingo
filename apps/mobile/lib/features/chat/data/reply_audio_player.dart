import 'package:flutter/services.dart';

class ReplyAudioPlayer {
  ReplyAudioPlayer({this.channelSuffix = 'ReplyAudio'});

  static const _channel = MethodChannel('bingo/device_tools');
  final String channelSuffix;
  bool _started = false;
  bool _mayHaveAudio = false;
  int _generation = 0;

  Future<void> add(Uint8List bytes) async {
    final generation = _generation;
    if (!_started) {
      _mayHaveAudio = true;
      await _channel.invokeMethod<void>('start$channelSuffix');
      if (generation != _generation) return;
      _started = true;
    }
    for (var offset = 0; offset < bytes.length; offset += 16000) {
      if (generation != _generation) return;
      final end = (offset + 16000).clamp(0, bytes.length);
      await _channel.invokeMethod<void>(
          'play$channelSuffix', Uint8List.sublistView(bytes, offset, end));
    }
  }

  Future<void> finish() async {
    final generation = _generation;
    if (_started) await _channel.invokeMethod<void>('finish$channelSuffix');
    if (generation == _generation) _started = false;
  }

  Future<void> stop() async {
    _generation++;
    _started = false;
    if (!_mayHaveAudio) return;
    _mayHaveAudio = false;
    try {
      await _channel.invokeMethod<void>('stop$channelSuffix');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
