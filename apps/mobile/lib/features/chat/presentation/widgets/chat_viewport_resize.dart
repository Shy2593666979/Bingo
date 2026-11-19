import 'package:flutter/material.dart';

/// Keep the reading anchor when the keyboard or an in-layout composer panel
/// changes the viewport. Newest messages stay above the composer; history does
/// not jump to the bottom just because a panel was opened.
class ChatViewportResize extends StatefulWidget {
  const ChatViewportResize(
      {required this.controller, required this.child, super.key});
  final ScrollController controller;
  final Widget child;
  @override
  State<ChatViewportResize> createState() => _ChatViewportResizeState();
}

class _ChatViewportResizeState extends State<ChatViewportResize> {
  double? _height;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final previousHeight = _height;
        _height = constraints.maxHeight;
        final scroll = widget.controller;
        if (previousHeight != null &&
            (previousHeight - constraints.maxHeight).abs() > .1 &&
            scroll.hasClients &&
            scroll.position.hasContentDimensions) {
          final position = scroll.position;
          final stickToBottom = position.extentAfter < 48;
          final offset = position.pixels;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !scroll.hasClients ||
                scroll.position.isScrollingNotifier.value) {
              return;
            }
            final updated = scroll.position;
            final target = stickToBottom
                ? updated.maxScrollExtent
                : offset
                    .clamp(updated.minScrollExtent, updated.maxScrollExtent)
                    .toDouble();
            if ((updated.pixels - target).abs() > .1) scroll.jumpTo(target);
          });
        }
        return widget.child;
      });
}
