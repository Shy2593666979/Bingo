import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';

/// A: a temporary row after the latest message, with text beside the AI avatar.
class ChatTypingHint extends StatefulWidget {
  const ChatTypingHint(
      {required this.name,
      required this.role,
      this.onAvatarTap,
      this.onAvatarLongPress,
      super.key});
  final String name;
  final String? role;
  final VoidCallback? onAvatarTap, onAvatarLongPress;
  @override
  State<ChatTypingHint> createState() => _ChatTypingHintState();
}

class _ChatTypingHintState extends State<ChatTypingHint>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
    } else {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: Semantics(
          label: '${widget.name}正在输入',
          liveRegion: true,
          child: ExcludeSemantics(
              child: Padding(
                  key: const ValueKey('chat-typing-hint'),
                  padding: const EdgeInsets.only(top: 5, bottom: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ChatPortrait(
                        size: 36,
                        onTap: widget.onAvatarTap,
                        onLongPress: widget.onAvatarLongPress,
                        child: AssistantAvatar(role: widget.role, size: 36)),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text('正在输入',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF7A958A)))),
                    const SizedBox(width: 7),
                    AnimatedBuilder(
                        animation: _animation,
                        builder: (context, _) =>
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              for (var i = 0; i < 3; i++)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 1.5),
                                    child: Opacity(
                                        opacity: .3 +
                                            .7 *
                                                ((math.sin((_animation.value -
                                                                i * .16) *
                                                            math.pi *
                                                            2) +
                                                        1) /
                                                    2),
                                        child: const DecoratedBox(
                                            decoration: BoxDecoration(
                                                color: Color(0xFF8DA89D),
                                                shape: BoxShape.circle),
                                            child:
                                                SizedBox.square(dimension: 3))))
                            ])),
                  ])))));
}
