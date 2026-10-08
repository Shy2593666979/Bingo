import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bingo/core/config/app_config.dart';
import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/chat/models/chat_location.dart';

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

class ChatAudio extends ChatStreamEvent {
  const ChatAudio(this.bytes);
  final Uint8List bytes;
}

class ChatAudioDone extends ChatStreamEvent {
  const ChatAudioDone();
}

class ChatAudioError extends ChatStreamEvent {
  const ChatAudioError(this.message);
  final String message;
}

abstract interface class ReplySpeechGateway {
  bool get readAloud;
  set readAloud(bool enabled);
  Future<void> stopReplySpeech();
}

abstract interface class MomentGateway {
  Stream<ChatStreamEvent> generateMoment(
      {required String conversationId,
      required String runId,
      required String mode,
      required String previous,
      required int seconds,
      required double charactersPerSecond,
      required bool closing});
  Future<void> cancelMoment(String runId);
  Stream<ChatStreamEvent> finishMoment(
      {required String conversationId,
      required String sessionId,
      required String feature,
      required String summary});
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
    this.result,
  });

  final String id;
  final String tool;
  final String title;
  final String description;
  final Map<String, dynamic> arguments;
  final String status;
  final String? result;

  DeviceAction copyWith({String? status, String? result}) => DeviceAction(
        id: id,
        tool: tool,
        title: title,
        description: description,
        arguments: arguments,
        status: status ?? this.status,
        result: result ?? this.result,
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
        result: json['result'] as String?,
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
    this.roleId,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final String? roleId;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        roleId: json['role_id'] as String?,
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

abstract interface class RoleGateway {
  Future<List<RoleOption>> listRoles();
  Future<RoleOption> saveRole(
      {String? id,
      required String name,
      required String prompt,
      String? roleType,
      String? personality,
      String? avatarData,
      String? voiceSourceId,
      List<String>? categories,
      List<String>? traits,
      bool draft = false});
  Future<void> deleteRole(String id);
  Future<String> cloneRoleVoice(String id, Uint8List audio);
  Future<Map<String, dynamic>> voiceJob(String id);
  Future<Uint8List> previewRoleVoice(String id);
}

class UserDetailsResult {
  const UserDetailsResult(this.user, this.recoveryCode);
  final UserProfile user;
  final String? recoveryCode;
}

abstract interface class UserDetailsGateway {
  Future<UserDetailsResult> saveUserDetails({
    required String nickname,
    required String gender,
    required DateTime birthday,
    String? avatarData,
  });
}

abstract interface class AccountGateway {
  Future<String> setupRecovery(DateTime birthday);
  Future<String> resetPassword(
      {required String phone,
      required String username,
      required DateTime birthday,
      required String recoveryCode,
      required String newPassword});
  Future<void> changePassword(String oldPassword, String newPassword);
}

abstract interface class RoleConversationGateway {
  Future<ConversationSummary> openRoleConversation(String roleId);
  Future<void> markConversationRead(String conversationId);
  Future<List<String>> getConversationRecommendations(String conversationId);
  Future<void> clearConversationRecommendations(String conversationId);
}

abstract interface class LocationGateway {
  Stream<ChatStreamEvent> sendLocation(
      {String? conversationId,
      required ChatLocation location,
      required String runId,
      String? supersedesRunId});
  Future<List<ChatLocation>> searchLocations(String keywords,
      {String city = ''});
  Future<({ChatLocation location, List<ChatLocation> places})> reverseLocation(
      double longitude, double latitude,
      {String coordinateSystem = 'GCJ-02'});
  String locationMapUrl(ChatLocation location, {int zoom = 15});
}

class HttpApiGateway
    implements
        AuthGateway,
        UserDetailsGateway,
        AccountGateway,
        RoleGateway,
        RoleConversationGateway,
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
        PushGateway,
        LocationGateway,
        ReplySpeechGateway,
        MomentGateway {
  HttpApiGateway({required this.config});

  final AppConfig config;
  final HttpClient _client = HttpClient();
  String? accessToken;
  @override
  bool readAloud = false;
  final Set<String> _speechRuns = {};
  final Map<String, HttpClient> _momentClients = {};

  @override
  Future<void> cancelMoment(String runId) async {
    _momentClients.remove(runId)?.close(force: true);
    try {
      await _request('POST', config.endpoint('/chat/speech/$runId/stop'));
    } on Exception {
      return;
    }
  }

  @override
  Stream<ChatStreamEvent> generateMoment(
      {required String conversationId,
      required String runId,
      required String mode,
      required String previous,
      required int seconds,
      required double charactersPerSecond,
      required bool closing}) async* {
    final client = HttpClient();
    _momentClients[runId] = client;
    try {
      final request = await client
          .postUrl(config.endpoint('/moments/stream'))
          .timeout(const Duration(seconds: 15));
      _prepareRequest(request);
      request.write(jsonEncode({
        'conversation_id': conversationId,
        'run_id': runId,
        'mode': mode,
        'previous': previous,
        'seconds': seconds,
        'characters_per_second': charactersPerSecond,
        'closing': closing
      }));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const ApiException('陪伴连接失败，请重试');
      }
      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 60))) {
        if (line.trim().isEmpty) continue;
        final event = jsonDecode(line) as Map<String, dynamic>;
        switch (event['type']) {
          case 'narrative':
            yield ChatSegment(event['content'] as String);
          case 'audio':
            yield ChatAudio(base64Decode(event['data'] as String));
          case 'audio_done':
            yield const ChatAudioDone();
          case 'error':
          case 'audio_error':
            throw const ApiException('陪伴声音暂时不可用，请重试');
        }
      }
    } finally {
      _momentClients.remove(runId);
      client.close(force: true);
    }
  }

  @override
  Stream<ChatStreamEvent> finishMoment(
      {required String conversationId,
      required String sessionId,
      required String feature,
      required String summary}) async* {
    final result =
        await _request('POST', config.endpoint('/moments/finish'), body: {
      'conversation_id': conversationId,
      'session_id': sessionId,
      'feature': feature,
      'summary': summary
    }) as Map<String, dynamic>;
    final createdAt = DateTime.parse(result['created_at'] as String);
    yield ChatStarted(conversationId,
        userMessageId: result['user_message_id'] as String,
        createdAt: createdAt);
    yield ChatSegment(result['content'] as String);
    yield ChatFinished(result['message_id'] as String,
        createdAt: createdAt,
        assistantRole: result['assistant_role'] as String?);
  }

  @override
  Future<void> stopReplySpeech() async {
    for (final runId in _speechRuns.toList()) {
      try {
        await _request('POST', config.endpoint('/chat/speech/$runId/stop'));
      } catch (_) {
        continue;
      }
    }
  }

  @override
  Future<ConversationSummary> openRoleConversation(String roleId) async {
    final json =
        await _request('POST', config.endpoint('/roles/$roleId/conversation'))
            as Map<String, dynamic>;
    return ConversationSummary.fromJson(json);
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    await _request(
        'POST', config.endpoint('/conversations/$conversationId/read'));
  }

  @override
  Future<List<String>> getConversationRecommendations(
      String conversationId) async {
    final json = await _request(
            'GET',
            config
                .endpoint('/recommendations')
                .replace(queryParameters: {'conversation_id': conversationId}))
        as Map<String, dynamic>;
    return List<String>.from(json['items'] as List? ?? []);
  }

  @override
  Future<void> clearConversationRecommendations(String conversationId) async {
    await _request(
        'DELETE',
        config
            .endpoint('/recommendations')
            .replace(queryParameters: {'conversation_id': conversationId}));
  }

  @override
  String locationMapUrl(ChatLocation location, {int zoom = 15}) =>
      config.endpoint('/locations/map').replace(queryParameters: {
        'longitude': '${location.longitude}',
        'latitude': '${location.latitude}',
        'zoom': '$zoom'
      }).toString();

  @override
  Future<List<ChatLocation>> searchLocations(String keywords,
      {String city = ''}) async {
    final json = await _request(
            'GET',
            config
                .endpoint('/locations/search')
                .replace(queryParameters: {'keywords': keywords, 'city': city}))
        as Map<String, dynamic>;
    return (json['places'] as List)
        .map((item) =>
            ChatLocation.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  @override
  Future<({ChatLocation location, List<ChatLocation> places})> reverseLocation(
      double longitude, double latitude,
      {String coordinateSystem = 'GCJ-02'}) async {
    final json = await _request(
        'GET',
        config.endpoint('/locations/reverse').replace(queryParameters: {
          'longitude': '$longitude',
          'latitude': '$latitude',
          'coordinate_system': coordinateSystem
        })) as Map<String, dynamic>;
    return (
      location: ChatLocation.fromJson(
          Map<String, dynamic>.from(json['location'] as Map)),
      places: (json['places'] as List)
          .map((item) =>
              ChatLocation.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList()
    );
  }

  @override
  Stream<ChatStreamEvent> sendLocation(
          {String? conversationId,
          required ChatLocation location,
          required String runId,
          String? supersedesRunId}) =>
      send(
          conversationId: conversationId,
          content: '',
          runId: runId,
          supersedesRunId: supersedesRunId,
          location: location);

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
    ChatLocation? location,
  }) async* {
    final uri = config.endpoint('/chat/stream');
    final spoken = readAloud;
    final request =
        await _client.postUrl(uri).timeout(const Duration(seconds: 15));
    _prepareRequest(request);
    request.write(jsonEncode({
      'conversation_id': conversationId,
      if (spoken) 'read_aloud': true,
      if (location != null) 'location': location.toJson(),
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

    if (spoken) _speechRuns.add(runId);
    if (spoken && !readAloud) unawaited(stopReplySpeech());
    try {
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
          case 'audio':
            yield ChatAudio(base64Decode(json['data'] as String));
          case 'audio_done':
            yield const ChatAudioDone();
          case 'audio_error':
            yield ChatAudioError(json['message'] as String);
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
    } finally {
      _speechRuns.remove(runId);
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
        'status': !succeeded
            ? 'failed'
            : (result?.startsWith('已提交给系统') ?? false)
                ? 'submitted'
                : 'succeeded',
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
        final detail = error['message'] ?? error['detail'];
        if (detail is String) {
          message = detail;
        } else if (detail is List && detail.isNotEmpty && detail.first is Map) {
          message = (detail.first as Map)['msg']?.toString() ?? message;
        }
      } on FormatException {
        if (payload.isNotEmpty) message = payload;
      }
      throw ApiException(message, statusCode: response.statusCode);
    }
    final result = _decodeResponse(payload) as Map<String, dynamic>;
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
    RoleAvatarStore.clear();
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

  Future<UserProfile> updatePersonality(String personality) async {
    final result = await _request('PUT', config.endpoint('/me/personality'),
        body: {'personality': personality}) as Map<String, dynamic>;
    return UserProfile.fromJson(result);
  }

  @override
  Future<String> setupRecovery(DateTime birthday) async {
    final result = await _request(
            'POST', config.endpoint('/me/recovery-profile'),
            body: {'birthday': birthday.toIso8601String().substring(0, 10)})
        as Map<String, dynamic>;
    return result['recovery_code'] as String;
  }

  @override
  Future<UserDetailsResult> saveUserDetails({
    required String nickname,
    required String gender,
    required DateTime birthday,
    String? avatarData,
  }) async {
    final result =
        await _request('PUT', config.endpoint('/me/user-profile'), body: {
      'username': nickname,
      'gender': gender,
      'birthday': birthday.toIso8601String().substring(0, 10),
      'user_avatar_data': avatarData,
    }) as Map<String, dynamic>;
    return UserDetailsResult(
        UserProfile.fromJson(result['user'] as Map<String, dynamic>),
        result['recovery_code'] as String?);
  }

  @override
  Future<String> resetPassword(
      {required String phone,
      required String username,
      required DateTime birthday,
      required String recoveryCode,
      required String newPassword}) async {
    final result =
        await _request('POST', config.endpoint('/auth/reset-password'), body: {
      'phone': phone,
      'username': username,
      'birthday': birthday.toIso8601String().substring(0, 10),
      'recovery_code': recoveryCode,
      'new_password': newPassword,
    }) as Map<String, dynamic>;
    return result['recovery_code'] as String;
  }

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async {
    await _request('POST', config.endpoint('/me/password'),
        body: {'old_password': oldPassword, 'new_password': newPassword});
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

  @override
  Future<List<RoleOption>> listRoles() async {
    final json = await _request('GET', config.endpoint('/roles')) as List;
    return json
        .map((item) =>
            RoleOption.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  @override
  Future<RoleOption> saveRole(
      {String? id,
      required String name,
      required String prompt,
      String? roleType,
      String? personality,
      String? avatarData,
      String? voiceSourceId,
      List<String>? categories,
      List<String>? traits,
      bool draft = false}) async {
    final json = await _request(id == null ? 'POST' : 'PUT',
        config.endpoint(id == null ? '/roles' : '/roles/$id'),
        body: {
          'name': name,
          'prompt': prompt,
          if (roleType != null) 'role_type': roleType,
          if (personality != null) 'personality': personality,
          'avatar_data': avatarData,
          'voice_source_id': voiceSourceId,
          'draft': draft,
          if (categories != null) 'categories': categories,
          if (traits != null) 'traits': traits,
        }) as Map<String, dynamic>;
    return RoleOption.fromJson(json);
  }

  @override
  Future<void> deleteRole(String id) async {
    await _request('DELETE', config.endpoint('/roles/$id'));
  }

  @override
  Future<String> cloneRoleVoice(String id, Uint8List audio) async {
    final json = await _request(
            'POST', config.endpoint('/roles/$id/voice-clone'),
            body: {'audio': base64Encode(audio), 'consent': true})
        as Map<String, dynamic>;
    return json['id'] as String;
  }

  @override
  Future<Map<String, dynamic>> voiceJob(String id) async =>
      await _request('GET', config.endpoint('/voice-jobs/$id'))
          as Map<String, dynamic>;

  @override
  Future<Uint8List> previewRoleVoice(String id) async {
    final json = await _request(
        'POST', config.endpoint('/roles/$id/voice-preview'),
        responseTimeout: const Duration(seconds: 100)) as Map<String, dynamic>;
    return base64Decode(json['audio'] as String);
  }

  Future<Object?> _request(String method, Uri uri,
      {Map<String, dynamic>? body,
      bool authenticated = true,
      Duration responseTimeout = const Duration(seconds: 60)}) async {
    final request =
        await _client.openUrl(method, uri).timeout(const Duration(seconds: 15));
    _prepareRequest(request, authenticated: authenticated);
    if (body != null) request.write(jsonEncode(body));

    final response = await request.close().timeout(responseTimeout);
    final payload =
        await response.transform(utf8.decoder).join().timeout(responseTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = '请求失败 (${response.statusCode})';
      try {
        final error = jsonDecode(payload) as Map<String, dynamic>;
        message = (error['message'] ?? error['detail']) as String? ?? message;
      } on FormatException {
        if (payload.isNotEmpty) message = payload;
      }
      throw ApiException(message, statusCode: response.statusCode);
    }
    return _decodeResponse(payload);
  }

  Object? _decodeResponse(String payload) {
    if (payload.isEmpty) return null;
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic> &&
        decoded.containsKey('code') &&
        decoded.containsKey('data')) {
      if (decoded['code'] != 0) {
        throw ApiException(decoded['message']?.toString() ?? '请求失败');
      }
      return decoded['data'];
    }
    return decoded;
  }

  Future<void> saveCurrentRegion(Map<String, String> region) async {
    await _request('PUT', config.endpoint('/me/location'), body: region);
  }

  Future<void> clearCurrentRegion() async {
    await _request('DELETE', config.endpoint('/me/location'));
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
