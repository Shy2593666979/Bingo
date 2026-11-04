import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar(
      {this.avatarData,
      this.username = '',
      required this.size,
      this.backgroundColor,
      this.foregroundColor,
      this.backgroundGradient,
      super.key});

  final String? avatarData;
  final String username;
  final double size;
  final Color? backgroundColor, foregroundColor;
  final Gradient? backgroundGradient;

  static const initialBackground = Color(0xFFE2EFE8);
  static const initialForeground = Color(0xFF3C6B58);
  static const emptyBackground = Color(0xFFF2F5F3);
  static const tones = [
    (background: Color(0xFFE2EFE8), foreground: Color(0xFF3C6B58)),
    (background: Color(0xFFE5EDF5), foreground: Color(0xFF3F607A)),
    (background: Color(0xFFECE7F4), foreground: Color(0xFF6C5486)),
    (background: Color(0xFFF7E6DF), foreground: Color(0xFF885A46)),
    (background: Color(0xFFF3EBDD), foreground: Color(0xFF7A653E)),
    (background: Color(0xFFF3E3E8), foreground: Color(0xFF88556B)),
  ];

  /// Distribute names across a soft palette without changing on rebuilds.
  static ({Color background, Color foreground}) toneFor(String username) {
    var hash = 2166136261;
    for (final rune in username.trim().runes) {
      hash = ((hash ^ rune) * 16777619) & 0xffffffff;
    }
    return tones[hash % tones.length];
  }

  static String initialFor(String username) {
    final name = username.trim();
    return name.isEmpty ? '' : name.characters.last;
  }

  static bool _looksLikeImage(Uint8List bytes) =>
      (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50) || // PNG
      (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) || // JPEG
      (bytes.length >= 4 && bytes[0] == 0x47 && bytes[1] == 0x49) || // GIF
      (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[8] == 0x57); // WEBP

  Widget _defaultAvatar() {
    final initial = initialFor(username);
    final tone = toneFor(username);
    final content = Center(
        child: initial.isEmpty
            ? null
            : Text(initial,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                    fontSize: size * .42,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: foregroundColor ?? tone.foreground)));
    return Semantics(
        label: initial.isEmpty ? '未设置头像' : '${username.trim()}的头像',
        excludeSemantics: true,
        child: backgroundGradient != null && initial.isNotEmpty
            ? DecoratedBox(
                decoration: BoxDecoration(gradient: backgroundGradient),
                child: content)
            : ColoredBox(
                color: initial.isEmpty
                    ? emptyBackground
                    : backgroundColor ?? tone.background,
                child: content));
  }

  Widget _frame(Widget child) => AvatarFrame(size: size, child: child);

  @override
  Widget build(BuildContext context) {
    final data = avatarData;
    if (data != null && data.isNotEmpty) {
      try {
        final bytes = base64Decode(data);
        if (_looksLikeImage(bytes)) {
          return _frame(Image.memory(bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultAvatar()));
        }
      } on FormatException {
        // Invalid or missing uploads use the nickname initial.
      }
    }
    return _frame(_defaultAvatar());
  }
}
