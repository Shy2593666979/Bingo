import 'dart:convert';

import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:flutter/services.dart';

class LocalConversationSummary {
  const LocalConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
}

class LocalConversation {
  const LocalConversation({
    required this.id,
    required this.title,
    required this.messages,
    List<Object>? timelineItems,
  }) : timelineItems = timelineItems ?? messages;

  final String id;
  final String title;
  final List<ChatMessage> messages;
  final List<Object> timelineItems;

  factory LocalConversation.fromJson(Map<Object?, Object?> json) {
    final rawMessages = json['messages']! as List<Object?>;
    final messages = rawMessages
        .cast<Map<Object?, Object?>>()
        .map(
          (message) => ChatMessage(
            id: message['id']! as String,
            role:
                message['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
            content: message['content']! as String,
            location: _location(message['location_json']),
            type: _messageType(message['message_type']),
            imageId: message['image_id'] as String?,
            createdAt: message['created_at'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    (message['created_at']! as num).toInt(),
                  ),
            assistantRole: message['assistant_role'] as String?,
            runId: message['run_id'] as String?,
            status: _messageStatus(message['status']),
            callStatus: message['call_status'] as String?,
            callDurationSeconds:
                (message['call_duration_seconds'] as num?)?.toInt(),
          ),
        )
        .toList(growable: false);
    final timelineJson = json['timeline_json'] as String?;
    final timelineItems = timelineJson == null
        ? <Object>[...messages]
        : (jsonDecode(timelineJson) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map<Object>((item) {
            if (item['kind'] == 'device_action') {
              return DeviceAction.fromJson(item);
            }
            return ChatMessage(
              id: item['id'] as String,
              role: item['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
              content: item['content'] as String,
              location: _location(item['location_json']),
              type: _messageType(item['message_type']),
              imageId: item['image_id'] as String?,
              createdAt: item['created_at'] == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      (item['created_at'] as num).toInt(),
                    ),
              assistantRole: item['assistant_role'] as String?,
              runId: item['run_id'] as String?,
              status: _messageStatus(item['status']),
              callStatus: item['call_status'] as String?,
              callDurationSeconds:
                  (item['call_duration_seconds'] as num?)?.toInt(),
            );
          }).toList(growable: false);
    return LocalConversation(
      id: json['id']! as String,
      title: json['title']! as String,
      messages: messages,
      timelineItems: timelineItems,
    );
  }
}

abstract interface class LocalChatStore {
  Future<LocalConversation?> loadActive(String userId);
  Future<List<LocalConversationSummary>> listConversations(String userId);
  Future<LocalConversation?> loadConversation(
    String userId,
    String conversationId,
  );
  Future<void> saveConversation({
    required String userId,
    required String conversationId,
    required String title,
    required List<ChatMessage> messages,
    DateTime? updatedAt,
    List<Object>? timelineItems,
  });
  Future<void> setActive(String userId, String? conversationId);
  Future<void> close();
}

class AndroidLocalChatStore implements LocalChatStore {
  static const _channel = MethodChannel('bingo/local_chat');

  @override
  Future<LocalConversation?> loadActive(String userId) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'loadActive',
      {'user_id': userId},
    );
    return result == null ? null : LocalConversation.fromJson(result);
  }

  @override
  Future<List<LocalConversationSummary>> listConversations(
      String userId) async {
    final rows = await _channel.invokeListMethod<Object?>(
          'listConversations',
          {'user_id': userId},
        ) ??
        const [];
    return rows
        .cast<Map<Object?, Object?>>()
        .map(
          (row) => LocalConversationSummary(
            id: row['id']! as String,
            title: row['title']! as String,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updated_at']! as int,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<LocalConversation?> loadConversation(
    String userId,
    String conversationId,
  ) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'loadConversation',
      {'user_id': userId, 'conversation_id': conversationId},
    );
    return result == null ? null : LocalConversation.fromJson(result);
  }

  @override
  Future<void> saveConversation({
    required String userId,
    required String conversationId,
    required String title,
    required List<ChatMessage> messages,
    DateTime? updatedAt,
    List<Object>? timelineItems,
  }) async {
    final timeline = timelineItems ?? messages;
    await _channel.invokeMethod<void>('saveConversation', {
      'user_id': userId,
      'conversation_id': conversationId,
      'title': title,
      'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'timeline_json': jsonEncode([
        for (final item in timeline)
          switch (item) {
            final ChatMessage message => {
                'kind': 'message',
                'id': message.id,
                'role': message.role.name,
                'content': message.content,
                'location_json': message.location == null
                    ? null
                    : jsonEncode(message.location!.toJson()),
                'message_type': message.type.name,
                'image_id': message.imageId,
                'created_at': message.createdAt?.millisecondsSinceEpoch,
                'assistant_role': message.assistantRole,
                'run_id': message.runId,
                'status': message.status.name,
                'call_status': message.callStatus,
                'call_duration_seconds': message.callDurationSeconds,
              },
            final DeviceAction action => {
                'kind': 'device_action',
                'id': action.id,
                'tool': action.tool,
                'title': action.title,
                'description': action.description,
                'arguments': action.arguments,
                'status': action.status,
              },
            _ => throw StateError('Unsupported local timeline item'),
          },
      ]),
      'messages': [
        for (final message in messages)
          {
            'id': message.id,
            'role': message.role.name,
            'content': message.content,
            'location_json': message.location == null
                ? null
                : jsonEncode(message.location!.toJson()),
            'message_type': message.type.name,
            'image_id': message.imageId,
            'created_at': message.createdAt?.millisecondsSinceEpoch,
            'assistant_role': message.assistantRole,
            'run_id': message.runId,
            'status': message.status.name,
            'call_status': message.callStatus,
            'call_duration_seconds': message.callDurationSeconds,
          },
      ],
    });
  }

  @override
  Future<void> setActive(String userId, String? conversationId) async {
    await _channel.invokeMethod<void>('setActive', {
      'user_id': userId,
      'conversation_id': conversationId,
    });
  }

  @override
  Future<void> close() => _channel.invokeMethod<void>('close');
}

ChatMessageStatus _messageStatus(Object? value) {
  return ChatMessageStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ChatMessageStatus.completed,
  );
}

ChatLocation? _location(Object? value) => value == null
    ? null
    : ChatLocation.fromJson(
        Map<String, dynamic>.from(jsonDecode(value as String) as Map));

ChatMessageType _messageType(Object? value) =>
    ChatMessageType.values.firstWhere((type) => type.name == value,
        orElse: () => ChatMessageType.chat);
