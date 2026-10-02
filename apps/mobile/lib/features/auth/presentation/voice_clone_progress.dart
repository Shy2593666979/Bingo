import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class VoiceCloneProgress extends StatelessWidget {
  const VoiceCloneProgress({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black26,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(28),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Material(
                color: Colors.transparent,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.graphic_eq_rounded,
                      color: BingoPalette.blue, size: 36),
                  const SizedBox(height: 14),
                  const Text('正在复刻伙伴声音',
                      style:
                          TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: const LinearProgressIndicator(minHeight: 7),
                  ),
                  const SizedBox(height: 16),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  const Text('上传录音 → 复刻声音 → 验证音色',
                      style: TextStyle(fontSize: 12, color: Color(0xFF707B78))),
                  const SizedBox(height: 8),
                  const Text('处理时间由声音服务决定，请稍候',
                      style: TextStyle(fontSize: 12, color: Color(0xFF707B78))),
                ])),
          ),
        ),
      );
}
