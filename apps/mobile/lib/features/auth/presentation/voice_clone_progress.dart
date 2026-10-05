import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class VoiceCloneProgress extends StatelessWidget {
  const VoiceCloneProgress({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final stage = message.contains('上传') ||
            message.contains('等待') ||
            message.contains('准备录音')
        ? 0
        : message.contains('验证') || message.contains('试听')
            ? 2
            : 1;
    return Theme(
        data: buildMintTheme(context),
        child: Material(
            color: BingoPalette.mintBackground,
            child: SafeArea(
                child: Center(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset('assets/images/bingo_logo.png',
                                      width: 68, height: 68),
                                  const SizedBox(height: 24),
                                  const Text('让伙伴记住这个声音',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 25,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 12),
                                  const Text('请稍等一下，正在处理这段录音。',
                                      style:
                                          TextStyle(color: Color(0xFF7D918A))),
                                  const SizedBox(height: 30),
                                  for (var index = 0; index < 3; index++)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        child: Row(children: [
                                          Container(
                                              width: 32,
                                              height: 32,
                                              decoration: const BoxDecoration(
                                                  color: BingoPalette.mintTint,
                                                  shape: BoxShape.circle),
                                              alignment: Alignment.center,
                                              child: index < stage
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      size: 18,
                                                      color: BingoPalette
                                                          .mintPrimary)
                                                  : Text('${index + 1}',
                                                      style: TextStyle(
                                                          color: index == stage
                                                              ? BingoPalette
                                                                  .mintPrimary
                                                              : const Color(
                                                                  0xFF7D918A)))),
                                          const SizedBox(width: 14),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    [
                                                      '上传录音',
                                                      '云端复刻',
                                                      '验证音色'
                                                    ][index],
                                                    style: TextStyle(
                                                        fontWeight: index ==
                                                                stage
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        color: index == stage
                                                            ? BingoPalette
                                                                .mintPrimary
                                                            : const Color(
                                                                0xFF7D918A))),
                                                if (index == stage) ...[
                                                  const SizedBox(height: 5),
                                                  Text(message,
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                              0xFF7D918A))),
                                                ],
                                              ])),
                                        ])),
                                  const SizedBox(height: 20),
                                  ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: const LinearProgressIndicator(
                                          minHeight: 5,
                                          color: BingoPalette.mintPrimary,
                                          backgroundColor:
                                              BingoPalette.mintTint)),
                                  const SizedBox(height: 18),
                                  const Text('处理时间由声音服务决定，请稍候',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF7D918A))),
                                ])))))));
  }
}
