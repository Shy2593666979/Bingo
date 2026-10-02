import 'package:bingo/core/device/region_location_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bingo/region_location');
  const service = RegionLocationService();

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('native region bridge uploads no raw coordinates', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => {
                  'status': 'success',
                  'province': '北京市',
                  'city': '',
                  'district': '海淀区',
                  'latitude': '39.9',
                  'longitude': '116.3',
                });
    expect(await service.current(),
        {'province': '北京市', 'city': '', 'district': '海淀区'});
  });

  test('denied permission yields no fabricated region', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (call) async => {'status': 'denied'});
    expect(await service.current(), isNull);
  });

  test('enabled preference is isolated per user', () async {
    final enabled = <String, bool>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final userId = arguments['user_id'] as String;
      if (call.method == 'setEnabled') {
        enabled[userId] = arguments['enabled'] as bool;
        return null;
      }
      return enabled[userId] ?? true;
    });
    await service.setEnabled('one', false);
    expect(await service.isEnabled('one'), false);
    expect(await service.isEnabled('two'), true);
  });
}
