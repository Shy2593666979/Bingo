import 'dart:typed_data';

enum ChatRole { user, assistant }

enum ChatMessageType { chat, call }

enum ChatMessageStatus { streaming, interrupted, completed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.type = ChatMessageType.chat,
    this.createdAt,
    this.imageId,
    this.imageBytes,
    this.assistantRole,
    this.runId,
    this.status = ChatMessageStatus.completed,
    this.callStatus,
    this.callDurationSeconds,
  });

  final String id;
  final ChatRole role;
  final String content;
  final ChatMessageType type;
  final DateTime? createdAt;
  final String? imageId;
  final Uint8List? imageBytes;
  final String? assistantRole;
  final String? runId;
  final ChatMessageStatus status;
  final String? callStatus;
  final int? callDurationSeconds;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: json['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
        content: json['content'] as String,
        type: json['message_type'] == 'call'
            ? ChatMessageType.call
            : ChatMessageType.chat,
        imageId: json['image_id'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
        assistantRole: json['assistant_role'] as String?,
        runId: json['run_id'] as String?,
        status: ChatMessageStatus.values.firstWhere(
          (status) => status.name == json['status'],
          orElse: () => ChatMessageStatus.completed,
        ),
        callStatus: json['call_status'] as String?,
        callDurationSeconds: json['call_duration_seconds'] as int?,
      );

  ChatMessage copyWith({
    String? id,
    String? content,
    DateTime? createdAt,
    String? imageId,
    Uint8List? imageBytes,
    String? assistantRole,
    String? runId,
    ChatMessageStatus? status,
    ChatMessageType? type,
    String? callStatus,
    int? callDurationSeconds,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role,
      content: content ?? this.content,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      imageId: imageId ?? this.imageId,
      imageBytes: imageBytes ?? this.imageBytes,
      assistantRole: assistantRole ?? this.assistantRole,
      runId: runId ?? this.runId,
      status: status ?? this.status,
      callStatus: callStatus ?? this.callStatus,
      callDurationSeconds: callDurationSeconds ?? this.callDurationSeconds,
    );
  }
}
