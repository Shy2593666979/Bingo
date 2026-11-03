import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

Future<bool?> showBingoConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  IconData icon = Icons.info_outline_rounded,
  bool destructive = false,
}) =>
    showDialog<bool>(
        context: context,
        barrierColor: BingoPalette.ink.withValues(alpha: .45),
        builder: (_) => BingoConfirmDialog(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel,
            icon: icon,
            destructive: destructive));

/// Shared confirmation layout; dismissal never confirms the operation.
class BingoConfirmDialog extends StatelessWidget {
  const BingoConfirmDialog(
      {required this.title,
      required this.message,
      required this.confirmLabel,
      this.cancelLabel = '取消',
      this.icon = Icons.info_outline_rounded,
      this.destructive = false,
      super.key});
  final String title, message, confirmLabel, cancelLabel;
  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final accent = destructive ? const Color(0xFFD9525A) : BingoPalette.primary;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const labelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    return Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: accent.withValues(alpha: .08),
                          shape: BoxShape.circle),
                      child: Icon(icon, size: 24, color: accent)),
                  const SizedBox(height: 16),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: BingoPalette.ink)),
                  const SizedBox(height: 12),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: BingoPalette.muted)),
                  const SizedBox(height: 24),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFFF2F5F5),
                                foregroundColor: BingoPalette.ink,
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 12),
                                shape: shape,
                                textStyle: labelStyle),
                            child: Text(cancelLabel,
                                textAlign: TextAlign.center))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 12),
                                shape: shape,
                                textStyle: labelStyle),
                            child: Text(confirmLabel,
                                textAlign: TextAlign.center))),
                  ]),
                ]))));
  }
}
