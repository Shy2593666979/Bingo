import 'package:flutter/services.dart';

/// Uses Android's existing local MediaPlayer decoder; chat PCM is independent.
class IntroductionAudioPlayer {
  static const _channel = MethodChannel('bingo/device_tools');

  Future<void> play(Uint8List bytes) =>
      _channel.invokeMethod<void>('playPreviewAudio', bytes);

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopPreviewAudio');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
