import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class DeviceActionCard extends StatelessWidget {
  const DeviceActionCard({
    required this.action,
    required this.onApprove,
    required this.onReject,
    super.key,
  });

  final DeviceAction action;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final isPending = action.status == 'pending';
    final canRetry = action.status == 'failed';
    final isProcessing = action.status == 'processing';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12205F4F),
              blurRadius: 22,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: BingoPalette.brandGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.alarm_add_rounded,
                      color: Colors.white, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    action.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusLabel(status: action.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(action.description),
            if (action.result != null &&
                {
                  'failed',
                  'submitted',
                  'report_pending',
                  'failure_report_pending'
                }.contains(action.status)) ...[
              const SizedBox(height: 8),
              Text(action.result!,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onReject, child: const Text('取消')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('创建'),
                  ),
                ],
              ),
            ],
            if (canRetry) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试创建'),
                ),
              ),
            ],
            if (isProcessing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (status) {
      'succeeded' => ('已创建', Icons.check_circle_outline_rounded),
      'submitted' => ('待系统确认', Icons.schedule_rounded),
      'report_pending' => ('待同步', Icons.cloud_upload_outlined),
      'failure_report_pending' => ('失败 · 待同步', Icons.cloud_upload_outlined),
      'approved' => ('待设备反馈', Icons.schedule_rounded),
      'failed' => ('创建失败', Icons.error_outline_rounded),
      'rejected' => ('已取消', Icons.block_rounded),
      'processing' => ('处理中', Icons.sync_rounded),
      _ => ('待确认', Icons.shield_outlined),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
