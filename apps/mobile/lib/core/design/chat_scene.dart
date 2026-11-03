import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bingo/core/theme/app_theme.dart';

/// Shared materials for the sunlit, sage-and-ivory conversation scene.
abstract final class ChatScene {
  static Future<void> setNativeChrome(bool enabled) async {
    try {
      await const MethodChannel('bingo/device_tools')
          .invokeMethod<void>('setChatChrome', {'enabled': enabled});
    } on PlatformException catch (_) {
      // Desktop and older installations have no native page chrome.
    } on MissingPluginException catch (_) {}
  }

  static const ink = BingoPalette.ink;
  static const muted = BingoPalette.muted;
  static const accent = BingoPalette.sage;
  static const leaf = BingoPalette.userBubble;
  static const ivory = BingoPalette.surface;
}

class ChatGlass extends StatelessWidget {
  const ChatGlass({required this.child, this.bottom = false, super.key});
  final Widget child;
  final bool bottom;
  @override
  Widget build(BuildContext context) => ClipRect(
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
          child: DecoratedBox(
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .97),
                  border: Border(
                      bottom: bottom
                          ? BorderSide.none
                          : BorderSide(color: BingoPalette.line, width: .5))),
              child: child)));
}

class SageBubble extends StatelessWidget {
  const SageBubble(
      {required this.isUser,
      required this.child,
      this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      super.key});
  final bool isUser;
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isUser ? null : Colors.white.withValues(alpha: .94),
        gradient: isUser
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFFDDFBF2), const Color(0xFFD9F9EC)])
            : null,
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isUser ? 12 : 4),
            topRight: Radius.circular(isUser ? 4 : 12),
            bottomLeft: const Radius.circular(12),
            bottomRight: const Radius.circular(12)),
        border: Border.all(
            color: isUser ? const Color(0xFFD4F3E8) : BingoPalette.line,
            width: .6),
      ),
      child: child);
}
