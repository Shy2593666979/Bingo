import 'dart:convert';
import 'package:flutter/services.dart';

class CompanionStore {
  static const _channel = MethodChannel('bingo/local_chat');

  Future<Map<String, dynamic>> list(String userId) async {
    final values = await _channel.invokeMapMethod<String, String>(
        'listCompanionData', {'user_id': userId});
    return {
      for (final entry in (values ?? <String, String>{}).entries)
        entry.key: jsonDecode(entry.value),
    };
  }

  Future<dynamic> read(String userId, String key) async {
    try {
      final value = await _channel.invokeMethod<String>(
          'readCompanionData', {'user_id': userId, 'key': key});
      return value == null ? null : jsonDecode(value);
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> write(String userId, String key, dynamic data) async {
    await _channel.invokeMethod<void>('writeCompanionData',
        {'user_id': userId, 'key': key, 'data': jsonEncode(data)});
  }
}
