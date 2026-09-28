import 'package:flutter/services.dart';

class CallPreferencesStore {
  static const _channel = MethodChannel('bingo/secure_storage');

  Future<bool> readCaptionsEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('readCallCaptionsEnabled') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> writeCaptionsEnabled(bool enabled) =>
      _channel.invokeMethod<void>('writeCallCaptionsEnabled', enabled);
}
