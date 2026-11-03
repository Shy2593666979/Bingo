import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:flutter/foundation.dart';

class GroupController extends ChangeNotifier {
  GroupController(this.gateway, this.groupId);
  final GroupGateway gateway;
  final String groupId;
  ChatGroup? group;
  final List<GroupChatMessage> messages = [];
  String? error, runId, typingName;
  bool loading = true, sending = false, readEnabled = true, more = true;
  int? Function()? readLimit;
  int _lastReadSeq = 0;
  Timer? _timer;
  int _epoch = 0, _cursor = 0;
  bool _disposed = false, _polling = false;
  String? _pendingId, _pendingText;
  List<String> _pendingMentions = [];
  bool _pendingAll = false;
  List<Map<String, String>> _pendingTargets = [];
  String? _pendingQuote, _pendingFingerprint;
  Map<String, dynamic>? _pendingMedia;
  List<String> responseTargets = [];
  final Map<String, String> _optimisticRuns = {};
  final Map<String, Map<String, dynamic>> _outbox = {};
  final Map<String, String> _typingRoles = {};
  List<String> get typingRoleIds => _typingRoles.keys.toList();
  String get typingSummary {
    final names = _typingRoles.values.toSet().toList();
    if (names.isEmpty) return '搭子们正在输入…';
    if (names.length > 2) return '${names.first}等 ${names.length} 位搭子正在输入…';
    return '${names.join('、')}正在输入…';
  }

  int get respondedCount => messages
      .where((m) =>
          m.runId == runId &&
          m.status == 'completed' &&
          responseTargets.contains(m.roleId))
      .map((m) => m.roleId)
      .toSet()
      .length;
  bool get busy => runId != null;
  bool get canRetry => _pendingId != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final epoch = ++_epoch;
    _timer?.cancel();
    try {
      final info = await gateway.getGroup(groupId);
      final rows = await gateway.groupMessages(groupId);
      if (_disposed || epoch != _epoch) return;
      group = info;
      messages.removeWhere((m) => !m.local);
      for (final row in rows) {
        _upsert(row);
      }
      more = rows.length == 100;
      runId = info.activeRunId;
      _cursor = 0;
      error = null;
      if (runId != null) _startPolling();
      if (runId == null && info.welcomePending) _startWelcomePolling();
      await markRead();
    } catch (_) {
      if (!_disposed && epoch == _epoch) error = '群聊加载失败，请重试';
    } finally {
      if (!_disposed && epoch == _epoch) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> older() async {
    if (messages.isEmpty || !more) return;
    final rows =
        await gateway.groupMessages(groupId, before: messages.first.seq);
    if (_disposed) return;
    for (final message in rows) {
      _upsert(message);
    }
    more = rows.length == 100;
    _notify();
  }

  void _upsert(GroupChatMessage message) {
    if (message.type == 'user' && !message.local) {
      final localId = message.clientMessageId == null
          ? _optimisticRuns.remove(message.runId)
          : 'local-${message.clientMessageId}';
      _optimisticRuns.remove(message.runId);
      if (localId != null) {
        messages.removeWhere((m) => m.id == localId);
        _outbox.remove(localId);
      }
    }
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      messages.add(message);
    } else {
      messages[index] = message;
    }
    messages.sort((a, b) {
      if (a.local != b.local) return a.local ? 1 : -1;
      return a.seq.compareTo(b.seq);
    });
  }

  Future<bool> send(String text, List<String> mentions,
      {bool mentionAll = false,
      List<Map<String, String>> mentionTargets = const [],
      String? replyToMessageId,
      Map<String, dynamic>? media}) async {
    if (sending || text.trim().isEmpty) return false;
    final selected = mentions.toSet().toList()..sort();
    final fingerprint = jsonEncode(
        [text, selected, mentionAll, mentionTargets, replyToMessageId, media]);
    if (_pendingFingerprint != fingerprint) {
      _pendingId =
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      _pendingText = text;
      _pendingMentions = selected;
      _pendingAll = mentionAll;
      _pendingTargets = List.of(mentionTargets);
      _pendingQuote = replyToMessageId;
      _pendingMedia = media;
      _pendingFingerprint = fingerprint;
    }
    sending = true;
    error = null;
    final localId = 'local-$_pendingId';
    _outbox[localId] = {
      'id': _pendingId,
      'text': text,
      'roles': selected,
      'all': mentionAll,
      'targets': mentionTargets,
      'quote': replyToMessageId,
      'media': media,
      'fingerprint': fingerprint
    };
    if (!messages.any((m) => m.id == localId)) {
      final quote = messages.where((m) => m.id == replyToMessageId).firstOrNull;
      _upsert(GroupChatMessage.fromJson({
        'id': localId,
        'client_message_id': _pendingId,
        'run_id': localId,
        'seq': messages.isEmpty ? 1 : messages.last.seq + 1,
        'sender_type': 'user',
        'sender_role_id': null,
        'sender_name': group?.humanName ?? '我',
        'content': text,
        'attachment': media == null
            ? null
            : {
                if (media['images'] != null) 'type': 'image',
                if (media['images'] != null)
                  'local_data': (media['images'] as List).first['data'],
                if (media['location'] != null) 'type': 'location',
                if (media['location'] != null) 'location': media['location'],
              },
        'status': 'sending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'mentions': selected,
        'mention_all': mentionAll,
        'mention_targets': mentionTargets,
        'reply_to_message_id': replyToMessageId,
        'reply_to': quote == null
            ? null
            : {
                'id': quote.id,
                'sender_name': quote.name,
                'content': quote.content,
                'created_at': quote.createdAt.toIso8601String(),
              },
      }));
    } else {
      _setLocalStatus(localId, 'sending');
    }
    _notify();
    try {
      final api = gateway;
      final run = media != null && api is GroupMediaGateway
          ? await (api as GroupMediaGateway)
              .sendGroupMedia(groupId, text, _pendingId!, media)
          : api is GroupV2Gateway
              ? await (api as GroupV2Gateway).sendGroupV2(
                  groupId, text, selected, _pendingId!,
                  mentionAll: mentionAll,
                  mentionTargets: mentionTargets,
                  replyToMessageId: replyToMessageId)
              : await gateway.sendGroup(groupId, text, selected, _pendingId!);
      if (_disposed) return false;
      _epoch++;
      _timer?.cancel();
      runId = run;
      _cursor = 0;
      typingName = null;
      _typingRoles.clear();
      responseTargets = [];
      _optimisticRuns[run] = localId;
      _setLocalStatus(localId, 'accepted');
      _pendingId = null;
      _pendingText = null;
      _pendingFingerprint = null;
      _startPolling();
      unawaited(_refreshGroup(_epoch));
      return true;
    } on ApiException catch (e) {
      _setLocalStatus(localId, 'send_failed');
      error = e.message;
      return false;
    } catch (_) {
      _setLocalStatus(localId, 'send_failed');
      error = '消息发送未确认，点击重试不会重复发送';
      return false;
    } finally {
      sending = false;
      _notify();
    }
  }

  void _setLocalStatus(String id, String status) {
    final index = messages.indexWhere((m) => m.id == id);
    if (index >= 0) messages[index] = messages[index].withStatus(status);
  }

  Future<void> _refreshGroup(int epoch) async {
    try {
      final info = await gateway.getGroup(groupId);
      if (!_disposed && epoch == _epoch) {
        group = info;
        _notify();
      }
    } catch (_) {
      // Settings refresh never changes an already accepted send into a failure.
    }
  }

  Future<void> retry([String? localId]) async {
    if (sending) return;
    final saved = _outbox[localId];
    if (saved != null) {
      _pendingId = saved['id'] as String;
      _pendingText = saved['text'] as String;
      _pendingMentions = saved['roles'] as List<String>;
      _pendingAll = saved['all'] as bool;
      _pendingTargets = saved['targets'] as List<Map<String, String>>;
      _pendingQuote = saved['quote'] as String?;
      _pendingMedia = saved['media'] as Map<String, dynamic>?;
      _pendingFingerprint = saved['fingerprint'] as String;
    }
    if (_pendingText != null) {
      await send(_pendingText!, _pendingMentions,
          mentionAll: _pendingAll,
          mentionTargets: _pendingTargets,
          replyToMessageId: _pendingQuote,
          media: _pendingMedia);
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 450), (_) => poll());
    unawaited(poll());
  }

  void _startWelcomePolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _pollWelcome());
  }

  Future<void> _pollWelcome() async {
    if (_disposed || _polling || runId != null) return;
    _polling = true;
    final epoch = _epoch;
    try {
      final info = await gateway.getGroup(groupId);
      final rows = await gateway.groupMessages(groupId);
      if (_disposed || epoch != _epoch) return;
      group = info;
      for (final row in rows) {
        _upsert(row);
      }
      if (info.activeRunId != null) {
        runId = info.activeRunId;
        _cursor = 0;
        _startPolling();
      } else if (!info.welcomePending) {
        _timer?.cancel();
      }
      _notify();
      await markRead();
    } catch (_) {
      // Keep the next poll: welcome generation survives transient disconnects.
    } finally {
      _polling = false;
    }
  }

  Future<void> poll() async {
    final run = runId;
    if (run == null || _polling || _disposed) return;
    final epoch = _epoch;
    _polling = true;
    try {
      final batch = await gateway.groupEvents(groupId, run, _cursor);
      if (_disposed || epoch != _epoch) return;
      error = null;
      for (final raw in batch['events'] as List) {
        final event = Map<String, dynamic>.from(raw as Map);
        final seq = event['event_seq'] as int;
        if (seq <= _cursor) continue;
        if (event['message'] is Map) {
          _upsert(GroupChatMessage.fromJson(
              Map<String, dynamic>.from(event['message'] as Map)));
        }
        if (event['type'] == 'speaker_start') {
          typingName = event['name'] as String?;
          final roleId = event['role_id'] as String?;
          if (roleId != null) _typingRoles[roleId] = typingName ?? '搭子';
        }
        if (event['type'] == 'run_start') {
          responseTargets =
              (event['response_targets'] as List? ?? []).cast<String>();
        }
        if (event['type'] == 'speaker_error') {
          error = event['reason'] as String?;
          _typingRoles.remove(event['role_id']);
        }
        if (event['type'] == 'message_end') {
          typingName = null;
          if (event['message'] is Map) {
            _typingRoles.remove((event['message'] as Map)['sender_role_id']);
          }
        }
        if (event['type'] == 'run_error') error = event['message'] as String?;
        _cursor = seq;
      }
      if (['completed', 'cancelled', 'failed'].contains(batch['status']) &&
          batch['has_more'] != true) {
        runId = null;
        typingName = null;
        _typingRoles.clear();
        _timer?.cancel();
        final rows = await gateway.groupMessages(groupId);
        if (_disposed || epoch != _epoch) return;
        for (final message in rows) {
          _upsert(message);
        }
      }
      await markRead();
      _notify();
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        error = '连接中断，正在恢复群聊…';
        _notify();
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> markRead() async {
    final canonical = messages.where((m) => !m.local).toList();
    if (!readEnabled || canonical.isEmpty) return;
    final seq = readLimit == null ? canonical.last.seq : readLimit!();
    if (seq == null || seq <= _lastReadSeq) return;
    try {
      await gateway.readGroup(groupId, seq);
      _lastReadSeq = max(_lastReadSeq, seq);
    } catch (_) {/* Retry next poll. */}
  }

  Future<bool> locate(String id) async {
    if (messages.any((m) => m.id == id)) return true;
    final api = gateway;
    if (api is! GroupV2Gateway) return false;
    final rows = await (api as GroupV2Gateway).groupMessageContext(groupId, id);
    if (_disposed) return false;
    for (final row in rows) {
      _upsert(row);
    }
    _notify();
    return messages.any((m) => m.id == id);
  }

  Future<void> cancel() async {
    if (runId == null) return;
    try {
      await gateway.cancelGroupRun(groupId, runId!);
      await load();
    } catch (_) {
      error = '停止失败，请重试';
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    super.dispose();
  }
}
