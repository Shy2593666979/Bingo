import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/local_chat_store.dart';
import 'package:flutter/material.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    required this.store,
    required this.remote,
    required this.userId,
    required this.onOpenConversation,
    super.key,
  });

  final LocalChatStore store;
  final ConversationGateway remote;
  final String userId;
  final ValueChanged<LocalConversation> onOpenConversation;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<_ConversationEntry>> _conversations;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _conversations = _loadConversations();
    if (mounted) setState(() {});
  }

  Future<List<_ConversationEntry>> _loadConversations() async {
    final local = await widget.store.listConversations(widget.userId);
    final merged = <String, _ConversationEntry>{
      for (final item in local)
        item.id: _ConversationEntry(
          id: item.id,
          title: item.title,
          updatedAt: item.updatedAt,
        ),
    };
    try {
      final remote = await widget.remote.listConversations();
      for (final item in remote) {
        merged.putIfAbsent(
          item.id,
          () => _ConversationEntry(
            id: item.id,
            title: item.title,
            updatedAt: item.createdAt,
          ),
        );
      }
    } on Exception {
      // Local history remains available while the server is offline.
    }
    final result = merged.values.toList(growable: false);
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<void> _openConversation(_ConversationEntry summary) async {
    try {
      var conversation =
          await widget.store.loadConversation(widget.userId, summary.id);
      if (conversation == null) {
        final messages = await widget.remote.listMessages(summary.id);
        conversation = LocalConversation(
          id: summary.id,
          title: summary.title,
          messages: messages,
        );
        await widget.store.saveConversation(
          userId: widget.userId,
          conversationId: summary.id,
          title: summary.title,
          messages: messages,
          timelineItems: messages,
          updatedAt: summary.updatedAt,
        );
      }
      if (mounted) widget.onOpenConversation(conversation);
    } on Exception {
      if (!mounted) return;
      showCenterToast(context, '无法打开这条会话记录');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('会话记录', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh();
          await _conversations;
        },
        child: FutureBuilder<List<_ConversationEntry>>(
          future: _conversations,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _HistoryState(
                icon: Icons.storage_outlined,
                title: '无法读取本地记录',
                subtitle: '请稍后重试',
                onRetry: _refresh,
              );
            }
            final conversations = snapshot.data ?? const [];
            if (conversations.isEmpty) {
              return const _HistoryState(
                icon: Icons.forum_outlined,
                title: '暂无会话',
                subtitle: '开始对话后，记录会保存在手机中',
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = conversations[index];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  leading: CircleAvatar(
                    child: Text(item.title.characters.first.toUpperCase()),
                  ),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_formatDate(item.updatedAt)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openConversation(item),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.month}月${value.day}日 ${two(value.hour)}:${two(value.minute)}';
  }
}

class _ConversationEntry {
  const _ConversationEntry({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
}

class _HistoryState extends StatelessWidget {
  const _HistoryState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 150),
        Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ),
        ],
      ],
    );
  }
}
