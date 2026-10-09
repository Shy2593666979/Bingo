import 'package:bingo/core/device/device_tool_executor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bingo/device_tools');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('system alarm follows user confirmation without waiting for clock save',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'createAlarm');
      return 'system_alarm';
    });
    final result = await AndroidDeviceToolExecutor().execute(
        'device_alarm_create', {'scheduled_at': '2099-01-01T07:00:00+08:00'});
    expect(result, '用户已确认创建闹钟，按约定视为创建成功；已打开系统时钟');
    expect(result.startsWith('已提交给系统'), isFalse);
  });

  test('unavailable alarm still reports an execution failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
        AndroidDeviceToolExecutor().execute('device_alarm_create', {}),
        throwsA(isA<PlatformException>()));
  });
}
