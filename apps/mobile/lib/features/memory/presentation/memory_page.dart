import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/core/design/bingo_page.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class MemoryPage extends StatefulWidget {
  const MemoryPage({required this.gateway, super.key});

  final MemoryGateway gateway;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  late Future<List<MemoryItem>> _memories;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _memories = widget.gateway.listMemories();
    });
  }

  Future<void> _addMemory() async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加记忆'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '例如：我喜欢浅烘咖啡'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty) return;
    await widget.gateway.addMemory(content);
    _refresh();
  }

  Future<void> _deleteMemory(MemoryItem memory) async {
    await widget.gateway.deleteMemory(memory.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('长期记忆'),
        actions: [
          IconButton(
              onPressed: _refresh,
              tooltip: '刷新',
              icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: _addMemory,
              tooltip: '添加记忆',
              icon: const Icon(Icons.add)),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<MemoryItem>>(
        future: _memories,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return BingoEmptyState(
              icon: Icons.cloud_off_outlined,
              title: '无法读取记忆',
              message: '检查网络后，再试一次。',
              action: OutlinedButton(
                  onPressed: _refresh, child: const Text('重新加载')),
            );
          }
          final memories = snapshot.data ?? const [];
          if (memories.isEmpty) {
            return const BingoEmptyState(
              icon: Icons.psychology_outlined,
              title: '暂无长期记忆',
              message: '你可以手动添加，或在对话中说“记住……”',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: memories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final memory = memories[index];
              return BingoSection(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: const Icon(Icons.bookmark_outline_rounded),
                    title: Text(memory.content,
                        style: const TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: BingoPalette.ink)),
                    trailing: IconButton(
                      onPressed: () => _deleteMemory(memory),
                      tooltip: '删除记忆',
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ));
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMemory,
        tooltip: '添加记忆',
        child: const Icon(Icons.add),
      ),
    );
  }
}
