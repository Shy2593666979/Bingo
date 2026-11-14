import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Shared spacing and surfaces for forms, details, and settings.
class BingoSection extends StatelessWidget {
  const BingoSection({
    required this.child,
    this.title,
    this.subtitle,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final String? title, subtitle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title!,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 12, height: 1.5, color: BingoPalette.muted)),
            ],
            const SizedBox(height: 12),
          ],
          Material(
            color: BingoPalette.softSurface,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: padding, child: child),
          ),
        ],
      );
}

/// Keeps actions above the system gesture area, with a boundary from content.
class BingoActionBar extends StatelessWidget {
  const BingoActionBar({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: BingoPalette.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: child,
          ),
        ),
      );
}

class BingoEmptyState extends StatelessWidget {
  const BingoEmptyState(
      {required this.icon,
      required this.title,
      required this.message,
      this.action,
      super.key});
  final IconData icon;
  final String title, message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                    color: BingoPalette.softSurface, shape: BoxShape.circle),
                child: Icon(icon, size: 28, color: BingoPalette.muted),
              ),
              const SizedBox(height: 18),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, height: 1.7, color: BingoPalette.muted)),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ]),
          ),
        ),
      );
}
