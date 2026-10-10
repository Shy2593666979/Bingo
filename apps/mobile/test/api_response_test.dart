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
  final actionBodies = <Map<String, dynamic>>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    gateway = HttpApiGateway(
        config: AppConfig(
            apiBaseUri: Uri.parse('http://127.0.0.1:${server.port}')));
    gateway.accessToken = 'test-token';
    statusCode = 200;
    requests.clear();
    actionBodies.clear();
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      if (request.uri.path.contains('/device-actions/') ||
          request.uri.path.endsWith('/auth/reset-password') ||
          request.uri.path.endsWith('/me/account')) {
        actionBodies.add(Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map));
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

  tearDown(() async {
    gateway.close();
    await server.close(force: true);
  });

  test('account deletion sends explicit confirmation to authenticated API',
      () async {
    statusCode = 204;
    await gateway.deleteAccount();
    expect(requests, ['DELETE /api/v1/me/account']);
    expect(actionBodies, [
      {'confirmed': true}
    ]);
  });

  test('password reset sends phone nickname birthday without recovery code',
      () async {
    responseData = {'code': 0, 'message': '操作成功', 'data': <String, dynamic>{}};
    await gateway.resetPassword(
        phone: '13800138000',
        username: '小明',
        birthday: DateTime(2000, 5, 1),
        newPassword: 'newpassword123');
    expect(requests.single, 'POST /api/v1/auth/reset-password');
    expect(actionBodies.single, {
      'phone': '13800138000',
      'username': '小明',
      'birthday': '2000-05-01',
      'new_password': 'newpassword123',
    });
  });

  test('legacy submission records keep their original status', () async {
    responseData = {
      'code': 0,
      'message': '操作成功',
      'data': {
        'id': 'alarm',
        'tool': 'device_alarm_create',
        'arguments': <String, dynamic>{},
        'status': 'submitted',
        'result': '已提交给系统时钟创建闹钟',
      }
    };
    final action = await gateway.completeDeviceAction('alarm',
        succeeded: true, result: '已提交给系统时钟创建闹钟');
    expect(actionBodies.single['status'], 'submitted');
    expect(action.status, 'submitted');
    expect(action.result, '已提交给系统时钟创建闹钟');
  });

  test('confirmed system alarm reports success without a second confirmation',
      () async {
    const result = '用户已确认创建闹钟，按约定视为创建成功；已打开系统时钟';
    responseData = {
      'code': 0,
      'message': '操作成功',
      'data': {
        'id': 'alarm',
        'tool': 'device_alarm_create',
        'arguments': <String, dynamic>{},
        'status': 'succeeded',
        'result': result,
      }
    };
    final action = await gateway.completeDeviceAction('alarm',
        succeeded: true, result: result);
    expect(actionBodies.single['status'], 'succeeded');
    expect(action.status, 'succeeded');
    expect(result, contains('用户已确认'));
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
