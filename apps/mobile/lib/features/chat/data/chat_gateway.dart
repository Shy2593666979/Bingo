import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bingo/core/config/app_config.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/models/chat_message.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

class ChatStarted extends ChatStreamEvent {
  const ChatStarted(
    this.conversationId, {
    this.userMessageId,
    this.createdAt,
    this.imageId,
  });
  final String conversationId;
  final String? userMessageId;
  final DateTime? createdAt;
  final String? imageId;
}

class ChatSegment extends ChatStreamEvent {
  const ChatSegment(this.content);
  final String content;
}

class ChatFinished extends ChatStreamEvent {
  const ChatFinished(
    this.messageId, {
    this.createdAt,
    this.assistantRole,
  });
  final String messageId;
  final DateTime? createdAt;
  final String? assistantRole;
}

class ChatInterrupted extends ChatStreamEvent {
  const ChatInterrupted(this.runId);
  final String runId;
}

class IncomingCallInvitation {
  const IncomingCallInvitation({
    required this.id,
    required this.conversationId,
    required this.callerName,
    required this.reason,
    required this.expiresAt,
    this.callerRole,
    this.status = 'ringing',
  });

  final String id;
  final String conversationId;
  final String callerName;
  final String? callerRole;
  final String reason;
  final String status;
  final DateTime expiresAt;

  factory IncomingCallInvitation.fromJson(Map<String, dynamic> json) =>
      IncomingCallInvitation(
        id: (json['id'] ?? json['call_id']) as String,
        conversationId: json['conversation_id'] as String,
        callerName: json['caller_name'] as String? ?? 'Bingo',
        callerRole: json['caller_role'] as String?,
        reason: json['reason'] as String? ?? '想和你说说话',
        status: json['status'] as String? ?? 'ringing',
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class ChatIncomingCall extends ChatStreamEvent {
  const ChatIncomingCall(this.invitation);
  final IncomingCallInvitation invitation;
}

class DeviceAction {
  const DeviceAction({
    required this.id,
    required this.tool,
    required this.title,
    required this.description,
    required this.arguments,
    this.status = 'pending',
  });

  final String id;
  final String tool;
  final String title;
  final String description;
  final Map<String, dynamic> arguments;
  final String status;

  DeviceAction copyWith({String? status}) => DeviceAction(
        id: id,
        tool: tool,
        title: title,
        description: description,
        arguments: arguments,
        status: status ?? this.status,
      );

  factory DeviceAction.fromJson(Map<String, dynamic> json) => DeviceAction(
        id: (json['id'] ?? json['action_id']) as String,
        tool: json['tool'] as String,
        title: json['title'] as String? ?? '设备操作',
        description: json['description'] as String? ?? '',
        arguments: Map<String, dynamic>.from(
          json['arguments'] as Map<String, dynamic>,
        ),
        status: json['status'] as String? ?? 'pending',
      );
}

class ChatApprovalRequired extends ChatStreamEvent {
  const ChatApprovalRequired(this.action);
  final DeviceAction action;
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.createdAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String content;
  final DateTime createdAt;

  factory MemoryItem.fromJson(Map<String, dynamic> json) => MemoryItem(
        id: json['id'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ProactiveMessage {
  const ProactiveMessage({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.content,
    required this.stage,
    required this.createdAt,
    this.assistantRole,
  });

  final String id;
  final String conversationId;
  final String messageId;
  final String content;
  final int stage;
  final DateTime createdAt;
  final String? assistantRole;

  factory ProactiveMessage.fromJson(Map<String, dynamic> json) =>
      ProactiveMessage(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        messageId: json['message_id'] as String,
        content: json['content'] as String,
        stage: json['stage'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
        assistantRole: json['assistant_role'] as String?,
      );
}

abstract interface class ChatGateway {
  Stream<ChatStreamEvent> send({
    String? conversationId,
    required String content,
    required String runId,
    String? supersedesRunId,
    List<ChatImageUpload> images = const [],
  });
}

class ChatImageUpload {
  const ChatImageUpload({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

abstract interface class DeviceActionGateway {
  Future<DeviceAction> approveDeviceAction(String actionId);
  Future<void> rejectDeviceAction(String actionId);
  Future<DeviceAction> completeDeviceAction(
    String actionId, {
    required bool succeeded,
    String? result,
  });
}

abstract interface class ConversationGateway {
  Future<List<ConversationSummary>> listConversations();
  Future<List<ChatMessage>> listMessages(String conversationId);
}

abstract interface class ServerGateway {
  Future<bool> checkHealth();
}

abstract interface class SpeechGateway {
  Future<String> transcribe(Uint8List wavAudio);
}

abstract interface class RealtimeSpeechGateway {
  Future<RealtimeTranscriptionSession> startRealtimeTranscription();
}

abstract interface class RealtimeCallGateway {
  Future<WebSocket> connectRealtimeCall({
    String? conversationId,
    String? callId,
  });
}

abstract interface class CallInvitationGateway {
  Future<IncomingCallInvitation?> getPendingCallInvitation();
  Future<IncomingCallInvitation> acceptCallInvitation(String callId);
  Future<void> rejectCallInvitation(String callId);
  Future<void> missCallInvitation(String callId);
}

abstract interface class RealtimeTranscriptionSession {
  void addAudio(Uint8List pcmAudio);
  Future<String> finish();
  Future<void> cancel();
}

abstract interface class MemoryGateway {
  Future<List<MemoryItem>> listMemories();
  Future<MemoryItem> addMemory(String content);
  Future<void> deleteMemory(String memoryId);
}

abstract interface class EngagementGateway {
  Future<List<ProactiveMessage>> listProactiveMessages();
  Future<void> acknowledgeProactiveMessage(String id);
  Future<List<String>> getRecommendations();
  Future<void> clearRecommendations();
}

abstract interface class PushGateway {
  Future<void> registerPushDevice({
    required String installationId,
    required String clientId,
    String? manufacturer,
    String? model,
    String? appVersion,
  });

  Future<void> unregisterPushDevice(String installationId);
}

abstract interface class AuthGateway {
  Future<AuthResult> register(String phone, String password);
  Future<AuthResult> login(String phone, String password);
  Future<void> logout();
  Future<UserProfile> getProfile();
  Future<UserProfile> updateProfile({
    required String username,
    required String assistantName,
    required String personality,
    required String role,
  });
  Future<ProfileOptions> getProfileOptions();
}

class HttpApiGateway
    implements
        AuthGateway,
        ChatGateway,
        ConversationGateway,
        DeviceActionGateway,
        ServerGateway,
        SpeechGateway,
        RealtimeSpeechGateway,
        RealtimeCallGateway,
        CallInvitationGateway,
        MemoryGateway,
        EngagementGateway,
        PushGateway {
  HttpApiGateway({required this.config});

  final AppConfig config;
  final HttpClient _client = HttpClient();
  String? accessToken;

  String imageUrl(String imageId) => config
      .endpoint('/chat/images/${Uri.encodeComponent(imageId)}')
      .toString();

  @override
  Stream<ChatStreamEvent> send({
    String? conversationId,
    required String content,
    required String runId,
    String? supersedesRunId,
    List<ChatImageUpload> images = const [],
  }) async* {
    final uri = config.endpoint('/chat/stream');
    final request =
        await _client.postUrl(uri).timeout(const Duration(seconds: 15));
    _prepareRequest(request);
    request.write(jsonEncode({
      'conversation_id': conversationId,
      'content': content,
      'run_id': runId,
      'supersedes_run_id': supersedesRunId,
      'images': [
        for (final image in images)
          {
            'mime_type': image.mimeType,
            'data': base64Encode(image.bytes),
          },
      ],
    }));
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload = await response.transform(utf8.decoder).join();
      throw HttpException('HTTP ${response.statusCode}: $payload', uri: uri);
    }

    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final json = jsonDecode(line) as Map<String, dynamic>;
      switch (json['type']) {
        case 'start':
          yield ChatStarted(
            json['conversation_id'] as String,
            userMessageId: json['user_message_id'] as String?,
            imageId: json['image_id'] as String?,
            createdAt: json['created_at'] == null
                ? null
                : DateTime.parse(json['created_at'] as String),
          );
        case 'segment':
          yield ChatSegment(json['content'] as String);
        case 'done':
          yield ChatFinished(
            json['message_id'] as String,
            createdAt: json['created_at'] == null
                ? null
                : DateTime.parse(json['created_at'] as String),
            assistantRole: json['assistant_role'] as String?,
          );
        case 'interrupted':
          yield ChatInterrupted(json['run_id'] as String? ?? runId);
        case 'approval_required':
          yield ChatApprovalRequired(DeviceAction.fromJson(json));
        case 'incoming_call':
          yield ChatIncomingCall(IncomingCallInvitation.fromJson(json));
        case 'error':
          throw HttpException(json['message'] as String? ?? '服务端处理失败',
              uri: uri);
      }
    }
  }

  @override
  Future<DeviceAction> approveDeviceAction(String actionId) async {
    final json = await _request(
      'POST',
      config.endpoint('/device-actions/$actionId/approve'),
    ) as Map<String, dynamic>;
    return DeviceAction.fromJson(json);
  }

  @override
  Future<void> rejectDeviceAction(String actionId) async {
    await _request(
      'POST',
      config.endpoint('/device-actions/$actionId/reject'),
    );
  }

  @override
  Future<DeviceAction> completeDeviceAction(
    String actionId, {
    required bool succeeded,
    String? result,
  }) async {
    final json = await _request(
      'POST',
      config.endpoint('/device-actions/$actionId/complete'),
      body: {
        'status': succeeded ? 'succeeded' : 'failed',
        'result': result,
      },
    ) as Map<String, dynamic>;
    return DeviceAction.fromJson(json);
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    final json = await _request('GET', config.endpoint('/conversations'))
        as List<dynamic>;
    return json
        .cast<Map<String, dynamic>>()
        .map(ConversationSummary.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    final json = await _request(
      'GET',
      config.endpoint('/conversations/$conversationId/messages'),
    ) as List<dynamic>;
    return json
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList(growable: false);
  }

  @override
  Future<bool> checkHealth() async {
    try {
      final json = await _request('GET', config.endpoint('/health'))
          as Map<String, dynamic>;
      return json['status'] == 'ok';
    } on Exception {
      return false;
    }
  }

  @override
  Future<String> transcribe(Uint8List wavAudio) async {
    final uri = config.endpoint('/asr/transcribe');
    final request =
        await _client.postUrl(uri).timeout(const Duration(seconds: 15));
    _prepareRequest(request);
    request.headers.contentType = ContentType('audio', 'wav');
    request.contentLength = wavAudio.length;
    request.add(wavAudio);
    final response = await request.close().timeout(const Duration(seconds: 75));
    final payload = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = '语音识别失败 (${response.statusCode})';
      try {
        final error = jsonDecode(payload) as Map<String, dynamic>;
        message = error['detail'] as String? ?? message;
      } on FormatException {
        if (payload.isNotEmpty) message = payload;
      }
      throw ApiException(message, statusCode: response.statusCode);
    }
    final result = jsonDecode(payload) as Map<String, dynamic>;
    return (result['text'] as String? ?? '').trim();
  }

  @override
  Future<RealtimeTranscriptionSession> startRealtimeTranscription() async {
    final token = accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('请先登录');
    }
    final httpUri = config.endpoint('/asr/realtime');
    final uri =
        httpUri.replace(scheme: httpUri.scheme == 'https' ? 'wss' : 'ws');
    return _WebSocketTranscriptionSession.connect(uri, token);
  }

  @override
  Future<WebSocket> connectRealtimeCall({
    String? conversationId,
    String? callId,
  }) async {
    final token = accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('请先登录');
    }
    final httpUri = config.endpoint('/realtime/calls/stream');
    final query = <String, String>{
      if (conversationId != null) 'conversation_id': conversationId,
      if (callId != null) 'call_id': callId,
    };
    final uri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: query.isEmpty ? null : query,
    );
    return WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 15));
  }

  @override
  Future<IncomingCallInvitation?> getPendingCallInvitation() async {
    final json = await _request(
      'GET',
      config.endpoint('/call-invitations/pending'),
    );
    if (json == null) return null;
    return IncomingCallInvitation.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<IncomingCallInvitation> acceptCallInvitation(String callId) async {
    final json = await _request(
      'POST',
      config.endpoint('/call-invitations/$callId/accept'),
    ) as Map<String, dynamic>;
    return IncomingCallInvitation.fromJson(json);
  }

  @override
  Future<void> rejectCallInvitation(String callId) async {
    await _request(
      'POST',
      config.endpoint('/call-invitations/$callId/reject'),
    );
  }

  @override
  Future<void> missCallInvitation(String callId) async {
    await _request(
      'POST',
      config.endpoint('/call-invitations/$callId/miss'),
    );
  }

  @override
  Future<AuthResult> register(String phone, String password) async {
    final json = await _request(
      'POST',
      config.endpoint('/auth/register'),
      body: {'phone': phone, 'password': password},
      authenticated: false,
    ) as Map<String, dynamic>;
    return AuthResult.fromJson(json);
  }

  @override
  Future<AuthResult> login(String phone, String password) async {
    final json = await _request(
      'POST',
      config.endpoint('/auth/login'),
      body: {'phone': phone, 'password': password},
      authenticated: false,
    ) as Map<String, dynamic>;
    return AuthResult.fromJson(json);
  }

  @override
  Future<void> logout() async {
    await _request('POST', config.endpoint('/auth/logout'));
  }

  @override
  Future<UserProfile> getProfile() async {
    final json =
        await _request('GET', config.endpoint('/me')) as Map<String, dynamic>;
    return UserProfile.fromJson(json);
  }

  @override
  Future<UserProfile> updateProfile({
    required String username,
    required String assistantName,
    required String personality,
    required String role,
  }) async {
    final json = await _request(
      'PUT',
      config.endpoint('/me/profile'),
      body: {
        'username': username,
        'assistant_name': assistantName,
        'personality': personality,
        'role': role,
      },
    ) as Map<String, dynamic>;
    return UserProfile.fromJson(json);
  }

  @override
  Future<ProfileOptions> getProfileOptions() async {
    final json = await _request('GET', config.endpoint('/profile/options'))
        as Map<String, dynamic>;
    return ProfileOptions.fromJson(json);
  }

  @override
  Future<List<MemoryItem>> listMemories() async {
    final json =
        await _request('GET', config.endpoint('/memories')) as List<dynamic>;
    return json
        .cast<Map<String, dynamic>>()
        .map(MemoryItem.fromJson)
        .toList(growable: false);
  }

  @override
  Future<MemoryItem> addMemory(String content) async {
    final json = await _request(
      'POST',
      config.endpoint('/memories'),
      body: {'content': content},
    ) as Map<String, dynamic>;
    return MemoryItem.fromJson(json);
  }

  @override
  Future<void> deleteMemory(String memoryId) async {
    await _request('DELETE', config.endpoint('/memories/$memoryId'));
  }

  @override
  Future<List<ProactiveMessage>> listProactiveMessages() async {
    final json = await _request(
      'GET',
      config.endpoint('/proactive/messages'),
    ) as List<dynamic>;
    return json
        .cast<Map<String, dynamic>>()
        .map(ProactiveMessage.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> acknowledgeProactiveMessage(String id) async {
    await _request('POST', config.endpoint('/proactive/messages/$id/ack'));
  }

  @override
  Future<List<String>> getRecommendations() async {
    final json = await _request(
      'GET',
      config.endpoint('/recommendations'),
    ) as Map<String, dynamic>;
    return (json['items'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toList(growable: false);
  }

  @override
  Future<void> clearRecommendations() async {
    await _request('DELETE', config.endpoint('/recommendations'));
  }

  @override
  Future<void> registerPushDevice({
    required String installationId,
    required String clientId,
    String? manufacturer,
    String? model,
    String? appVersion,
  }) async {
    await _request(
      'PUT',
      config.endpoint('/push/devices'),
      body: {
        'installation_id': installationId,
        'provider': 'getui',
        'client_id': clientId,
        'manufacturer': manufacturer,
        'model': model,
        'app_version': appVersion,
      },
    );
  }

  @override
  Future<void> unregisterPushDevice(String installationId) async {
    await _request(
      'DELETE',
      config.endpoint('/push/devices/${Uri.encodeComponent(installationId)}'),
    );
  }

  Future<Object?> _request(String method, Uri uri,
      {Map<String, dynamic>? body, bool authenticated = true}) async {
    final request =
        await _client.openUrl(method, uri).timeout(const Duration(seconds: 15));
    _prepareRequest(request, authenticated: authenticated);
    if (body != null) request.write(jsonEncode(body));

    final response = await request.close().timeout(const Duration(seconds: 60));
    final payload = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = '请求失败 (${response.statusCode})';
      try {
        final error = jsonDecode(payload) as Map<String, dynamic>;
        message = error['detail'] as String? ?? message;
      } on FormatException {
        if (payload.isNotEmpty) message = payload;
      }
      throw ApiException(message, statusCode: response.statusCode);
    }
    return payload.isEmpty ? null : jsonDecode(payload);
  }

  void _prepareRequest(HttpClientRequest request, {bool authenticated = true}) {
    request.headers.contentType = ContentType.json;
    final token = accessToken;
    if (authenticated && token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
  }

  void close() => _client.close(force: true);
}

class _WebSocketTranscriptionSession implements RealtimeTranscriptionSession {
  _WebSocketTranscriptionSession._(this._socket);

  final WebSocket _socket;
  final Completer<String> _result = Completer<String>();
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;

  static Future<_WebSocketTranscriptionSession> connect(
    Uri uri,
    String token,
  ) async {
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 12));
    final session = _WebSocketTranscriptionSession._(socket);
    final ready = Completer<void>();
    session._subscription = socket.listen(
      (dynamic data) {
        try {
          final event = jsonDecode(data as String) as Map<String, dynamic>;
          switch (event['type']) {
            case 'ready':
              if (!ready.isCompleted) {
                ready.complete();
              }
            case 'completed':
              final text = (event['text'] as String? ?? '').trim();
              if (!session._result.isCompleted) {
                session._result.complete(text);
              }
            case 'error':
              final error = ApiException(
                event['message'] as String? ?? '实时语音识别失败',
              );
              if (!ready.isCompleted) {
                ready.completeError(error);
              }
              if (!session._result.isCompleted) {
                session._result.completeError(error);
              }
          }
        } on Exception catch (error) {
          if (!ready.isCompleted) {
            ready.completeError(error);
          }
          if (!session._result.isCompleted) {
            session._result.completeError(error);
          }
        }
      },
      onError: (Object error) {
        if (!ready.isCompleted) ready.completeError(error);
        if (!session._result.isCompleted) session._result.completeError(error);
      },
      onDone: () {
        const error = ApiException('实时语音连接已断开');
        if (!ready.isCompleted) ready.completeError(error);
        if (!session._result.isCompleted) session._result.completeError(error);
      },
      cancelOnError: true,
    );
    try {
      await ready.future.timeout(const Duration(seconds: 12));
      return session;
    } on Object {
      await session.cancel();
      rethrow;
    }
  }

  @override
  void addAudio(Uint8List pcmAudio) {
    if (!_closed && pcmAudio.isNotEmpty) _socket.add(pcmAudio);
  }

  @override
  Future<String> finish() async {
    if (_closed) throw const ApiException('实时语音连接已关闭');
    _socket.add(jsonEncode({'type': 'finish'}));
    try {
      return await _result.future.timeout(const Duration(seconds: 12));
    } finally {
      await cancel();
    }
  }

  @override
  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    await _socket.close(WebSocketStatus.normalClosure);
    await _subscription?.cancel();
  }
}
