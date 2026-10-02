import 'dart:convert';

import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({this.avatarData, required this.size, super.key});

  final String? avatarData;
  final double size;

  Widget _defaultAvatar() => Image.asset('assets/images/bingo_logo.png',
      width: size, height: size, fit: BoxFit.cover);

  @override
  Widget build(BuildContext context) {
    Widget image = _defaultAvatar();
    final data = avatarData;
    if (data != null && data.isNotEmpty) {
      try {
        image = Image.memory(base64Decode(data),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _defaultAvatar());
      } on FormatException {
        image = _defaultAvatar();
      }
    }
    return SizedBox.square(dimension: size, child: ClipOval(child: image));
  }
}
