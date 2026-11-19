import 'package:flutter/material.dart';

class RecentChatFeedback extends StatefulWidget {
  const RecentChatFeedback(
      {required this.onTap, required this.child, super.key});
  final VoidCallback onTap;
  final Widget child;
  @override
  State<RecentChatFeedback> createState() => _RecentChatFeedbackState();
}

class _RecentChatFeedbackState extends State<RecentChatFeedback> {
  bool _pressed = false, _opening = false;
  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _pressed = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    try {
      widget.onTap();
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _pressed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Material(
        color: _pressed ? const Color(0xFFF3F3F3) : Colors.transparent,
        child: InkWell(
          onTap: _open,
          onHighlightChanged: (value) {
            if (!_opening) setState(() => _pressed = value);
          },
          splashColor: const Color(0x0FEE5B88),
          highlightColor: const Color(0xFFF3F3F3),
          child: widget.child,
        ),
      );
}
