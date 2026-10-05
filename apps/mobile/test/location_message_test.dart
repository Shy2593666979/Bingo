import 'dart:convert';
import 'dart:async';

import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/local_chat_store.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/location_picker_page.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/widgets/location_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const point = ChatLocation(
  name: '天安门',
  address: '北京市东城区长安街北侧',
  province: '北京市',
  city: '北京市',
  district: '东城区',
  longitude: 116.397463,
  latitude: 39.909187,
);

class PlacesGateway implements LocationGateway, ChatGateway {
  String? searched;
  ChatLocation? sent;
  @override
  Stream<ChatStreamEvent> send(
          {String? conversationId,
          required String content,
          required String runId,
          String? supersedesRunId,
          List<ChatImageUpload> images = const []}) =>
      const Stream.empty();
  @override
  Future<List<ChatLocation>> searchLocations(String keywords,
      {String city = ''}) async {
    searched = keywords;
    return [point];
  }

  @override
  String locationMapUrl(ChatLocation location, {int zoom = 15}) =>
      'http://localhost/map';
  @override
  Future<({ChatLocation location, List<ChatLocation> places})> reverseLocation(
          double longitude, double latitude,
          {String coordinateSystem = 'GCJ-02'}) async =>
      (location: point, places: [point]);
  @override
  Stream<ChatStreamEvent> sendLocation(
      {String? conversationId,
      required ChatLocation location,
      required String runId,
      String? supersedesRunId}) async* {
    sent = location;
    yield ChatStarted('conversation',
        userMessageId: 'saved-user', createdAt: DateTime.utc(2026));
    yield const ChatSegment('这是你分享的地点。');
    yield const ChatFinished('reply');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'location JSON, pending-message replacement and old message compatibility',
      () {
    final message = ChatMessage.fromJson({
      'id': 'point',
      'role': 'user',
      'content': '[位置]',
      'message_type': 'location',
      'location': point.toJson(),
    });
    expect(message.copyWith(id: 'saved').location?.longitude, point.longitude);
    expect(message.type, ChatMessageType.location);
    expect(
        ChatMessage.fromJson({'id': 'old', 'role': 'user', 'content': '你好'})
            .type,
        ChatMessageType.chat);
    final region = point.asRegion().toJson();
    expect(region['name'], '北京市东城区');
    expect(region.containsKey('longitude'), false);
    expect(region.containsKey('latitude'), false);
    expect(region.containsKey('accuracy_m'), false);
  });

  test('local history restores location from messages and timeline', () {
    final stored = {
      'id': 'point',
      'role': 'user',
      'content': '[位置]',
      'message_type': 'location',
      'location_json': jsonEncode(point.toJson())
    };
    final conversation = LocalConversation.fromJson({
      'id': 'conversation',
      'title': '位置',
      'messages': [stored],
      'timeline_json': jsonEncode([
        {...stored, 'kind': 'message'}
      ]),
    });
    expect(conversation.messages.single.location?.name, point.name);
    expect(
        (conversation.timelineItems.single as ChatMessage).location?.latitude,
        point.latitude);
  });

  test('controller keeps location after server confirmation', () async {
    final gateway = PlacesGateway();
    final controller = ChatController(gateway: gateway);
    addTearDown(controller.dispose);
    await controller.sendLocation(point);
    expect(gateway.sent?.name, point.name);
    final user = controller.messages.first;
    expect(user.id, 'saved-user');
    expect(user.location?.longitude, point.longitude);
    expect(user.type, ChatMessageType.location);
    expect(controller.status, ChatStatus.idle);
  });

  test('map panning preserves center and moves selected coordinates', () {
    final unchanged = panLocation(point, Offset.zero, 360);
    expect(unchanged.latitude, closeTo(point.latitude!, 0.000001));
    expect(unchanged.longitude, point.longitude);
    final moved = panLocation(point, const Offset(30, 20), 360);
    expect(moved.longitude, lessThan(point.longitude!));
    expect(moved.latitude, greaterThan(point.latitude!));
    expect(moved.source, 'map');
  });

  test('nearby distances use real coordinates', () {
    expect(locationDistance(point, point), 0);
    expect(
        locationDistance(
            point,
            const ChatLocation(
                name: '附近',
                address: '附近',
                longitude: 116.398463,
                latitude: 39.909187)),
        closeTo(85.3, 1));
  });

  testWidgets(
      'reopening previews cache but cannot send stale location or leak accounts',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('bingo/region_location');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var requests = 0;
    final pending = Completer<Map<String, String>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'currentCoordinates') return null;
      requests++;
      if (requests == 1) {
        return {
          'status': 'success',
          'longitude': '116.397',
          'latitude': '39.909',
          'precise': 'true',
          'accuracy_m': '10'
        };
      }
      return pending.future;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final gateway = PlacesGateway();
    await tester.pumpWidget(
        MaterialApp(home: LocationPickerPage(gateway: gateway, userId: 'one')));
    await tester.pumpAndSettle();
    expect(find.text('当前位置'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        MaterialApp(home: LocationPickerPage(gateway: gateway, userId: 'one')));
    await tester.pump();
    expect(find.text('上次定位，仅供预览 · 正在更新'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '发送'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        MaterialApp(home: LocationPickerPage(gateway: gateway, userId: 'two')));
    await tester.pump();
    expect(find.text('上次定位，仅供预览 · 正在更新'), findsNothing);
    expect(find.text('正在定位，可先搜索地点'), findsOneWidget);
    pending.complete({'status': 'denied'});
    await tester.pumpAndSettle();
  });

  testWidgets('district card shows address, not JSON, and opens details',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LocationCard(location: point.asRegion()))));
    expect(find.text('北京市东城区'), findsNWidgets(2));
    expect(find.textContaining('longitude'), findsNothing);
    await tester.tap(find.byType(LocationCard));
    await tester.pumpAndSettle();
    expect(find.byType(LocationDetailPage), findsOneWidget);
    expect(find.text('仅分享区县，不包含精确位置'), findsOneWidget);
  });

  testWidgets(
      'denied permission still allows search and private region sending',
      (tester) async {
    const channel = MethodChannel('bingo/region_location');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel, (call) async => {'status': 'denied'});
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final gateway = PlacesGateway();
    ChatLocation? sent;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      sent = await Navigator.of(context).push<ChatLocation>(
                          MaterialPageRoute(
                              builder: (_) =>
                                  LocationPickerPage(gateway: gateway)));
                    },
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('定位权限未开启，仍可搜索地点发送'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '发送'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), '天安门');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(gateway.searched, '天安门');
    await tester.tap(find.widgetWithText(ListTile, '天安门'));
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(sent?.precision, 'district');
    expect(sent?.hasCoordinates, false);
  });
}
