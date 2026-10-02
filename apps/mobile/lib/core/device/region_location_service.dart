import 'package:flutter/services.dart';

class RegionLocationService {
  const RegionLocationService();

  static const _channel = MethodChannel('bingo/region_location');

  Future<bool> isEnabled(String userId) async =>
      await _channel.invokeMethod<bool>('getEnabled', {'user_id': userId}) ??
      true;

  Future<void> setEnabled(String userId, bool enabled) =>
      _channel.invokeMethod<void>(
          'setEnabled', {'user_id': userId, 'enabled': enabled});

  Future<Map<String, String>?> current({bool retry = false}) async {
    final value = await _channel
        .invokeMapMethod<String, String>('currentRegion', {'retry': retry});
    if (value?['status'] != 'success') return null;
    return {
      for (final key in ['province', 'city', 'district']) key: value![key] ?? ''
    };
  }

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}
