import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bingo/core/config/app_config.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late HttpApiGateway gateway;
  Object? responseData;
  int statusCode = 200;
  final requests = <String>[];
  final pushBodies = <Map<String, dynamic>>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    gateway = HttpApiGateway(
        config: AppConfig(
            apiBaseUri: Uri.parse('http://127.0.0.1:${server.port}')));
    gateway.accessToken = 'test-token';
    statusCode = 200;
    requests.clear();
    pushBodies.clear();
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      if (request.uri.path == '/api/v1/push/devices') {
        pushBodies.add(jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>);
      } else {
        await request.drain<void>();
      }
      request.response.statusCode = statusCode;
      if (statusCode != 204) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(responseData));
      }
      await request.response.close();
    });
  });

  test('push registration advertises avatar support only when enabled',
      () async {
    responseData = {
      'code': 0,
      'message': 'ok',
      'data': {'id': 'device'}
    };
    for (final enabled in [false, true]) {
      await gateway.registerPushDevice(
          installationId: 'installation-id',
          clientId: 'getui-client-id',
          roleAvatarNotifications: enabled);
      expect(pushBodies.last['role_avatar_notifications'], enabled);
    }
  });

  tearDown(() async {
    gateway.close();
    await server.close(force: true);
  });

  test('ASR unwraps JSON envelope without changing audio input', () async {
    responseData = {
      'code': 0,
      'message': '操作成功',
      'data': {'text': '今天心情很好'}
    };
    expect(await gateway.transcribe(Uint8List.fromList([1, 2, 3])), '今天心情很好');
  });

  test('keeps legacy response compatibility for rolling deployment', () async {
    responseData = {'text': '你好'};
    expect(await gateway.transcribe(Uint8List.fromList([1])), '你好');
  });

  test('reads unified business error message', () async {
    statusCode = 422;
    responseData = {'code': 422, 'message': '录入时间太短，请重新尝试', 'data': null};
    expect(
        gateway.transcribe(Uint8List.fromList([1])),
        throwsA(isA<ApiException>()
            .having((error) => error.message, 'message', '录入时间太短，请重新尝试')));
  });

  test('region update and 204 deletion use authenticated REST', () async {
    responseData = {
      'code': 0,
      'message': '操作成功',
      'data': {'display': '北京市海淀区'}
    };
    await gateway
        .saveCurrentRegion({'province': '北京市', 'city': '', 'district': '海淀区'});
    statusCode = 204;
    await gateway.clearCurrentRegion();
    expect(requests, ['PUT /api/v1/me/location', 'DELETE /api/v1/me/location']);
  });
}
