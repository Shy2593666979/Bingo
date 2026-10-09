import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';

class DeviceActionCard extends StatelessWidget {
  const DeviceActionCard({
    required this.action,
    required this.onApprove,
    required this.onReject,
    this.assistantRole,
    super.key,
  });

  final DeviceAction action;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final String? assistantRole;

  @override
  Widget build(BuildContext context) {
    final scheduledAt =
        DateTime.tryParse(action.arguments['scheduled_at']?.toString() ?? '')
            ?.toLocal();
    final time = scheduledAt == null
        ? action.description
        : '${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}';
    final now = DateUtils.dateOnly(DateTime.now());
    final date = scheduledAt == null ? null : DateUtils.dateOnly(scheduledAt);
    final day = date == now
        ? '今天'
        : date == now.add(const Duration(days: 1))
            ? '明天'
            : date == null
                ? null
                : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final recurrence = switch (action.arguments['recurrence']) {
      'daily' => '每天',
      'weekdays' => '工作日',
      _ => '不重复',
    };
    final metadata = [
      if (day != null) day,
      if (action.arguments['label'] case final String label)
        if (label.trim().isNotEmpty) label.trim(),
      recurrence,
    ].join(' · ');
    final rejected = action.status == 'rejected';
    final (statusLabel, statusIcon) = switch (action.status) {
      'succeeded' => ('创建成功', Icons.check_rounded),
      'submitted' => ('已交给系统时钟 · 待系统确认', Icons.schedule_rounded),
      'report_pending' => ('设备已执行 · 待同步', Icons.cloud_upload_outlined),
      'failure_report_pending' => ('创建失败 · 待同步', Icons.cloud_upload_outlined),
      'approved' => ('待设备反馈', Icons.schedule_rounded),
      'failed' => ('创建失败', Icons.error_outline_rounded),
      'rejected' => ('已拒绝 · 闹钟未创建', Icons.close_rounded),
      'processing' => ('正在处理…', Icons.schedule_rounded),
      _ => ('待确认', Icons.schedule_rounded),
    };
    final buttonShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(11));
    final confirmStyle = FilledButton.styleFrom(
        backgroundColor: const Color(0xFFBFE5D4),
        foregroundColor: const Color(0xFF365E49),
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        shape: buttonShape,
        side: const BorderSide(color: Color(0xFFAFD7C5)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AssistantAvatar(role: assistantRole, size: 34),
          const SizedBox(width: 9),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 13),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FCFA),
                border: Border.all(color: const Color(0xFFDEEBE3)),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F3EB),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.alarm_outlined,
                          color: Color(0xFF648775), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(time,
                              style: TextStyle(
                                  fontSize: scheduledAt == null ? 14 : 29,
                                  height: 1.2,
                                  color: const Color(0xFF21362D),
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          Text(metadata,
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF7B8C81))),
                        ],
                      ),
                    ),
                  ]),
                  if (action.status == 'pending') ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      OutlinedButton.icon(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB5403C),
                            backgroundColor: const Color(0xFFFFF0EF),
                            side: const BorderSide(color: Color(0xFFF1D1CE)),
                            minimumSize: const Size(84, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            shape: buttonShape),
                        icon: const Icon(Icons.close_rounded, size: 15),
                        label: const Text('拒绝'),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onApprove,
                          style: confirmStyle,
                          icon: const Icon(Icons.check_rounded, size: 15),
                          label: const Text('确认创建'),
                        ),
                      ),
                    ]),
                  ] else ...[
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFE0EBE4)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Icon(statusIcon,
                          size: 17,
                          color: rejected
                              ? const Color(0xFFB5403C)
                              : const Color(0xFF54765F)),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(statusLabel,
                            style: TextStyle(
                                fontSize: 12,
                                color: rejected
                                    ? const Color(0xFFB5403C)
                                    : const Color(0xFF54765F))),
                      ),
                    ]),
                    if (action.result != null &&
                        {'failed', 'failure_report_pending'}
                            .contains(action.status)) ...[
                      const SizedBox(height: 8),
                      Text(action.result!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (action.status == 'failed') ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                          onPressed: onApprove,
                          style: confirmStyle,
                          icon: const Icon(Icons.refresh_rounded, size: 15),
                          label: const Text('重试创建')),
                    ],
                    if (action.status == 'processing') ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(
                          color: Color(0xFF648775),
                          backgroundColor: Color(0xFFE6F3EB)),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
