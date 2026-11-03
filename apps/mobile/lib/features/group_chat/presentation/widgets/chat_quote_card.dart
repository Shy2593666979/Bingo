import 'package:flutter/material.dart';

/// A quiet source panel inside the reply bubble, following the chosen reference.
class ChatQuoteCard extends StatelessWidget {
  const ChatQuoteCard(
      {required this.sender,
      required this.content,
      required this.isUser,
      this.createdAt,
      this.unavailable = false,
      this.onTap,
      super.key});

  final String sender, content;
  final bool isUser, unavailable;
  final DateTime? createdAt;
  final VoidCallback? onTap;

  String? get _time {
    final value = createdAt?.toUtc().add(const Duration(hours: 8));
    return value == null
        ? null
        : '${value.hour.toString().padLeft(2, '0')}:'
            '${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final time = _time;
    return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
            color: isUser ? const Color(0xCFFFFFFF) : const Color(0xFFF3F6F8),
            borderRadius: BorderRadius.circular(9),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: unavailable ? null : onTap,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            Flexible(
                                child: Text(unavailable ? '原消息已不可用' : sender,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF738297)))),
                            if (!unavailable && time != null) ...[
                              const SizedBox(width: 9),
                              Text(time,
                                  style: const TextStyle(
                                      fontSize: 9.5, color: Color(0xFF8B9BAD))),
                            ]
                          ]),
                          if (!unavailable) ...[
                            const SizedBox(height: 4),
                            Text(content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    height: 1.4,
                                    color: Color(0xFF4E6172))),
                          ]
                        ])))));
  }
}
