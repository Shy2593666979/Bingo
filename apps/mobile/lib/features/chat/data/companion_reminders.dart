import 'package:flutter/services.dart';

class CompanionReminders {
  static const _channel = MethodChannel('bingo/device_tools');
  Future<void> schedule(
          {required String id,
          required String title,
          required String body,
          required DateTime time}) =>
      _channel.invokeMethod<void>('scheduleCompanionReminder', {
        'id': id,
        'title': title,
        'body': body,
        'time': time.millisecondsSinceEpoch
      });
  Future<void> cancel(String id) =>
      _channel.invokeMethod<void>('cancelCompanionReminder', {'id': id});
  Future<void> cancelAll() =>
      _channel.invokeMethod<void>('cancelAllCompanionReminders');
}
