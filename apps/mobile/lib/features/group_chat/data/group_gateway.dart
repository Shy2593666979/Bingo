import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/core/role_avatar_assets.dart';
import 'dart:typed_data';
import 'dart:io';

abstract interface class GroupCallGateway {
  Future<WebSocket> connectGroupCall(String groupId, List<String> roleIds);
}

abstract interface class GroupMediaGateway {
  Future<String> sendGroupMedia(
      String groupId, String text, String clientId, Map<String, dynamic> media);
  String groupImageUrl(String groupId, String messageId);
  String? get groupMediaToken;
}

abstract interface class GroupSpeechGateway {
  Stream<Uint8List> groupMessageSpeech(String groupId, String messageId);
  void stopGroupSpeech();
}

class GroupPerson {
  GroupPerson.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        roleName = json['role_name'] as String,
        active = json['active'] == true,
        avatarAsset = json['avatar_asset'] as String? ?? 'bingo_logo.png',
        avatarData = json['avatar_data'] as String? {
    RoleAvatarStore.set(roleName, avatarData,
        fallback: true,
        asset: roleAvatarFiles.contains(avatarAsset)
            ? 'assets/images/$avatarAsset'
            : null);
  }
  final String id, name, roleName, avatarAsset;
  final String? avatarData;
  final bool active;
}

class GroupChatMessage {
  GroupChatMessage.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        seq = json['seq'] as int,
        runId = json['run_id'] as String,
        type = json['sender_type'] as String,
        roleId = json['sender_role_id'] as String?,
        name = json['sender_name'] as String,
        content = json['content'] as String,
        attachment = json['attachment'] == null
            ? null
            : Map<String, dynamic>.from(json['attachment'] as Map),
        status = json['status'] as String,
        mentions = (json['mentions'] as List? ?? []).cast<String>(),
        mentionAll = json['mention_all'] == true,
        mentionTargets = (json['mention_targets'] as List? ?? [])
            .map((v) => Map<String, String>.from(v as Map))
            .toList(),
        replyToId = json['reply_to_message_id'] as String?,
        clientMessageId = json['client_message_id'] as String?,
        replyTo = json['reply_to'] == null
            ? null
            : Map<String, dynamic>.from(json['reply_to'] as Map),
        createdAt = DateTime.parse(json['created_at'] as String);
  final String id, runId, type, name, content, status;
  final Map<String, dynamic>? attachment;
  final String? roleId;
  final int seq;
  final DateTime createdAt;
  final List<String> mentions;
  final bool mentionAll;
  final List<Map<String, String>> mentionTargets;
  final String? replyToId;
  final String? clientMessageId;
  final Map<String, dynamic>? replyTo;
  bool get local => id.startsWith('local-');
  GroupChatMessage withStatus(String value) => GroupChatMessage.fromJson({
        'id': id,
        'run_id': runId,
        'seq': seq,
        'sender_type': type,
        'sender_role_id': roleId,
        'sender_name': name,
        'content': content,
        'attachment': attachment,
        'status': value,
        'created_at': createdAt.toIso8601String(),
        'mentions': mentions,
        'mention_all': mentionAll,
        'mention_targets': mentionTargets,
        'reply_to_message_id': replyToId,
        'reply_to': replyTo,
        'client_message_id': clientMessageId,
      });
}

class ChatGroup {
  ChatGroup.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        description = json['description'] as String? ?? '',
        cover = json['cover'] as String,
        members = (json['members'] as List)
            .map((item) =>
                GroupPerson.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        allowAiToAi = json['allow_ai_to_ai'] == true,
        mentionsEnabled = json['mentions_enabled'] == true,
        proactiveEnabled = json['proactive_enabled'] == true,
        muted = json['muted'] == true,
        readAloud = json['read_aloud'] != false,
        pinned = json['pinned'] == true,
        archived = json['archived'] == true,
        unread = json['unread_count'] as int? ?? 0,
        lastReadSeq = json['last_read_seq'] as int? ?? 0,
        welcomePending = json['welcome_pending'] == true,
        unreadMentions = json['unread_mentions'] as int? ?? 0,
        humanId = (json['human'] as Map?)?['id'] as String? ?? '',
        humanName = (json['human'] as Map?)?['name'] as String? ?? '我',
        activeRunId = json['active_run_id'] as String?,
        lastActivity = DateTime.parse(json['last_activity_at'] as String),
        lastMessage = json['last_message'] == null
            ? null
            : GroupChatMessage.fromJson(
                Map<String, dynamic>.from(json['last_message'] as Map));
  final String id, name, description, cover;
  final List<GroupPerson> members;
  final bool allowAiToAi, mentionsEnabled, proactiveEnabled, muted, pinned;
  final bool archived;
  final bool readAloud;
  final int unread;
  final int lastReadSeq;
  final bool welcomePending;
  final int unreadMentions;
  final String humanId, humanName;
  final String? activeRunId;
  final DateTime lastActivity;
  final GroupChatMessage? lastMessage;
  List<GroupPerson> get activeMembers =>
      members.where((person) => person.active).toList();

  String senderNameFor(GroupChatMessage message) {
    if (message.type != 'assistant') return message.name;
    final member =
        members.where((person) => person.id == message.roleId).firstOrNull;
    return member?.active == true ? member!.name : message.name;
  }
}

abstract interface class GroupV2Gateway {
  Future<String> sendGroupV2(
      String id, String text, List<String> mentions, String clientId,
      {bool mentionAll = false,
      List<Map<String, String>> mentionTargets = const [],
      String? replyToMessageId});
  Future<List<GroupChatMessage>> groupMessageContext(
      String id, String messageId);
}

abstract interface class GroupGateway {
  Future<List<ChatGroup>> listGroups();
  Future<ChatGroup> getGroup(String id);
  Future<ChatGroup> createGroup(Map<String, dynamic> data);
  Future<ChatGroup> updateGroup(String id, Map<String, dynamic> data);
  Future<ChatGroup> addGroupMembers(String id, List<String> roles);
  Future<ChatGroup> removeGroupMember(String id, String role);
  Future<List<GroupChatMessage>> groupMessages(String id, {int? before});
  Future<String> sendGroup(
      String id, String text, List<String> mentions, String clientId);
  Future<Map<String, dynamic>> groupEvents(String id, String run, int after);
  Future<void> cancelGroupRun(String id, String run);
  Future<void> readGroup(String id, int seq);
  Future<void> clearGroup(String id, {bool destroy = false});
}
