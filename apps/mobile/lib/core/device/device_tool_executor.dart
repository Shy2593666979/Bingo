import 'package:flutter/services.dart';

abstract interface class DeviceToolExecutor {
  Future<String> execute(String tool, Map<String, dynamic> arguments);
}

class AndroidDeviceToolExecutor implements DeviceToolExecutor {
  static const _channel = MethodChannel('bingo/device_tools');

  @override
  Future<String> execute(String tool, Map<String, dynamic> arguments) async {
    switch (tool) {
      case 'device_alarm_create':
        final mode =
            await _channel.invokeMethod<String>('createAlarm', arguments);
        if (mode == null) {
          throw PlatformException(
            code: 'alarm_unavailable',
            message: '无法创建闹钟',
          );
        }
        return mode == 'system_alarm' ? '已提交给系统时钟创建闹钟' : '已由 Bingo 在设备本地创建闹钟';
      default:
        throw PlatformException(
          code: 'unsupported_tool',
          message: '不支持的设备工具：$tool',
        );
    }
  }
}
