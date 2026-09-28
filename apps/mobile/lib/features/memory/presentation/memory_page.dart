import 'package:bingo/features/chat/data/chat_gateway.dart';
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
        title:
            const Text('长期记忆', style: TextStyle(fontWeight: FontWeight.w700)),
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
            return const Center(child: Text('无法读取记忆'));
          }
          final memories = snapshot.data ?? const [];
          if (memories.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 44,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text('暂无长期记忆',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('你可以手动添加，或在对话中说“记住……”'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: memories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final memory = memories[index];
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: Text(memory.content),
                trailing: IconButton(
                  onPressed: () => _deleteMemory(memory),
                  tooltip: '删除记忆',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              );
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
