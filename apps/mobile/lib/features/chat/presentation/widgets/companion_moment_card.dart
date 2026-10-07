import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/presentation/widgets/chat_menu_icon.dart';
import 'package:flutter/material.dart';

class CompanionMomentCard extends StatelessWidget {
  const CompanionMomentCard({required this.content, super.key});
  final String content;
  static final _prefix = RegExp(r'^\[(一起专注|小约定|陪我入睡|今日小记)\]\s*');
  static bool matches(String content) => _prefix.hasMatch(content);

  @override
  Widget build(BuildContext context) {
    final match = _prefix.firstMatch(content)!;
    final title = match.group(1)!;
    final icon = switch (title) {
      '一起专注' => ChatMenuSymbol.focus,
      '小约定' => ChatMenuSymbol.promise,
      '陪我入睡' => ChatMenuSymbol.sleep,
      _ => ChatMenuSymbol.diary,
    };
    final text = content
        .substring(match.end)
        .split('\n想和你分享')
        .first
        .replaceAll('。不要再创建闹钟。', '。');
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            ChatMenuIcon(symbol: icon, size: 21),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          SelectableText(text,
              style: const TextStyle(
                  fontSize: 15, height: 1.55, color: BingoPalette.ink)),
        ]);
  }
}
