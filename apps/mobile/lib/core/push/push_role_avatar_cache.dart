import 'dart:io';

import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:flutter/services.dart';

abstract final class PushRoleAvatarCache {
  static const _channel = MethodChannel('bingo/push');

  static Future<void> sync(String userId, List<RoleOption> roles) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cacheRoleAvatars', {
        'user_id': userId,
        'avatars': {
          for (final role in roles)
            if (role.avatarData != null) role.id: role.avatarData,
        },
      });
    } on Exception {
      return;
    }
  }
}
