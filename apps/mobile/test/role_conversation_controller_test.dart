import 'dart:async';

import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/local_chat_store.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThreadGateway
    implements
        ChatGateway,
        ConversationGateway,
        RoleConversationGateway,
        EngagementGateway {
  final streams = <String, StreamController<ChatStreamEvent>>{};
  final history = <String, List<ChatMessage>>{
    'girlfriend': [
      const ChatMessage(id: 'first', role: ChatRole.user, content: '女朋友专属故事')
    ],
    'boyfriend': [],
  };
  String? cleared;

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async =>
      history[conversationId] ?? [];
  @override
  Future<List<ConversationSummary>> listConversations() async => [];
  @override
  Stream<ChatStreamEvent> send(
      {String? conversationId,
      required String content,
      required String runId,
      String? supersedesRunId,
      List<ChatImageUpload> images = const []}) {
    final stream = StreamController<ChatStreamEvent>();
    streams[runId] = stream;
    return stream.stream;
  }

  @override
  Future<List<String>> getConversationRecommendations(
          String conversationId) async =>
      ['$conversationId 的话题'];
  @override
  Future<void> clearConversationRecommendations(String conversationId) async =>
      cleared = conversationId;
  @override
  Future<List<ProactiveMessage>> listProactiveMessages() async => [];
  @override
  Future<List<String>> getRecommendations() =>
      throw StateError('Should use scoped recommendations');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThreadStore implements LocalChatStore {
  String? savedUser;
  @override
  Future<LocalConversation?> loadConversation(
          String userId, String conversationId) async =>
      null;
  @override
  Future<void> saveConversation(
      {required String userId,
      required String conversationId,
      required String title,
      required List<ChatMessage> messages,
      DateTime? updatedAt,
      List<Object>? timelineItems}) async {
    savedUser = userId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
      'role binding restores only its thread and ignores previous stream updates',
      () async {
    final gateway = _ThreadGateway();
    final store = _ThreadStore();
    final controller = ChatController(
        gateway: gateway,
        remoteHistory: gateway,
        localStore: store,
        engagement: gateway);
    addTearDown(controller.dispose);
    await controller.bindConversation('user', 'girlfriend', '女朋友');
    expect(controller.messages.single.content, '女朋友专属故事');
    expect(store.savedUser, 'user:conversation:girlfriend');
    expect(controller.recommendations, ['girlfriend 的话题']);
    final sending = controller.send('继续聊聊');
    await Future<void>.delayed(Duration.zero);
    final previousStream = gateway.streams.values.single;
    await controller.bindConversation('user', 'boyfriend', '男朋友');
    previousStream.add(const ChatSegment('迟到的女朋友回复'));
    previousStream.add(const ChatFinished('old-message'));
    await previousStream.close();
    await sending;
    expect(controller.messages, isEmpty);
    expect(controller.conversationId, 'boyfriend');
    expect(controller.recommendations, ['boyfriend 的话题']);
    await controller.bindConversation('user', 'girlfriend', '女朋友');
    expect(controller.messages.single.content, '女朋友专属故事');
  });
}
