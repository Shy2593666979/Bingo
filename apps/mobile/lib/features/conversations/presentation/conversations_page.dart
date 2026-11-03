import 'dart:async';

import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/community/presentation/community_widgets.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage(
      {required this.gateway,
      required this.onOpenRole,
      required this.onFindCompanion,
      super.key});
  final RoleGateway gateway;
  final Future<void> Function(RoleOption) onOpenRole;
  final VoidCallback onFindCompanion;
  @override
  State<ConversationsPage> createState() => ConversationsPageState();
}

class ConversationsPageState extends State<ConversationsPage> {
  List<RoleOption>? _roles;
  String _query = '';
  bool _failed = false, _loading = false;
  String? _opening;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final roles = await widget.gateway.listRoles();
      final chats = roles
          .where((role) => role.conversationId != null && role.messageCount > 0)
          .toList();
      chats.sort((a, b) {
        final pin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
        return pin != 0
            ? pin
            : (b.lastMessageAt ?? DateTime(2000))
                .compareTo(a.lastMessageAt ?? DateTime(2000));
      });
      if (mounted) {
        setState(() {
          _roles = chats;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _loading = false;
    }
  }

  Future<void> _open(RoleOption role) async {
    if (_opening != null) return;
    setState(() => _opening = role.id);
    try {
      await widget.onOpenRole(role);
      await refresh();
    } catch (_) {
      if (mounted) showCenterToast(context, '暂时无法进入聊天，请重试');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = _roles
        ?.where((role) =>
            role.displayName.contains(_query) ||
            (role.lastMessage?.contains(_query) ?? false))
        .toList();
    return ColoredBox(
        color: communityBackground,
        child: SafeArea(
            bottom: false,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.fromLTRB(22, 24, 22, 7),
                  child: Text('聊天',
                      style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: communityInk))),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: Text('每一段对话，都从这里继续',
                      style: TextStyle(fontSize: 12, color: communityMuted))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: TextField(
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                      decoration: InputDecoration(
                          hintText: '搜索最近的聊天',
                          hintStyle: const TextStyle(fontSize: 13),
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 21),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none)))),
              Expanded(
                  child: RefreshIndicator(
                      onRefresh: refresh,
                      child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          children: [
                            if (_failed)
                              CommunityEmpty(
                                  title: '聊天列表加载失败',
                                  description: '请检查连接后重试。',
                                  action: '重新加载',
                                  onAction: refresh)
                            else if (roles == null)
                              const Padding(
                                  padding: EdgeInsets.all(50),
                                  child: Center(
                                      child: CircularProgressIndicator()))
                            else if (roles.isEmpty)
                              CommunityEmpty(
                                  title:
                                      _query.isEmpty ? '先和搭子打个招呼吧' : '没有找到相关聊天',
                                  description: _query.isEmpty
                                      ? '最近聊过的搭子会出现在这里。'
                                      : '换一个名字或关键词试试。',
                                  action: '去我的搭子',
                                  onAction: _query.isEmpty
                                      ? widget.onFindCompanion
                                      : null)
                            else
                              for (final role in roles)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 9),
                                    child: Material(
                                        color: role.pinned
                                            ? const Color(0xFFEEF3EB)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(19),
                                        child: InkWell(
                                            onTap: _opening == null
                                                ? () => _open(role)
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(19),
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(15),
                                                child: Row(children: [
                                                  AssistantAvatar(
                                                      role: role.name,
                                                      size: 51),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                        Row(children: [
                                                          Expanded(
                                                              child: Text(
                                                                  role
                                                                      .displayName,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          16,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      color:
                                                                          communityInk))),
                                                          if (role.muted)
                                                            const Icon(
                                                                Icons
                                                                    .notifications_off_outlined,
                                                                size: 14,
                                                                color:
                                                                    communityMuted),
                                                          if (role.pinned)
                                                            const Icon(
                                                                Icons
                                                                    .push_pin_rounded,
                                                                size: 13,
                                                                color:
                                                                    communityMuted),
                                                          if (role.lastMessageAt !=
                                                              null)
                                                            Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        left:
                                                                            5),
                                                                child: Text(
                                                                    _time(role
                                                                        .lastMessageAt!),
                                                                    style: const TextStyle(
                                                                        fontSize:
                                                                            10,
                                                                        color:
                                                                            communityMuted))),
                                                        ]),
                                                        const SizedBox(
                                                            height: 7),
                                                        Row(children: [
                                                          Expanded(
                                                              child: Text(
                                                                  role.lastMessage ??
                                                                      '',
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      color:
                                                                          communityMuted))),
                                                          if (role.unreadCount > 0)
                                                            Container(
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical:
                                                                        2),
                                                                decoration: BoxDecoration(
                                                                    color: role.muted
                                                                        ? const Color(
                                                                            0xFFAAB5AE)
                                                                        : const Color(
                                                                            0xFFD29394),
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            12)),
                                                                child: Text(
                                                                    role.unreadCount >
                                                                            99
                                                                        ? '99+'
                                                                        : '${role.unreadCount}',
                                                                    style: const TextStyle(
                                                                        color:
                                                                            Colors.white,
                                                                        fontSize: 10))),
                                                        ]),
                                                      ])),
                                                ]))))),
                          ]))),
            ])));
  }
}

String _time(DateTime date) {
  final local = date.toUtc().add(const Duration(hours: 8));
  final now = DateTime.now().toUtc().add(const Duration(hours: 8));
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month}/${local.day}';
}
