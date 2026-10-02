import 'dart:convert';

import 'package:flutter/foundation.dart';

abstract final class RoleAvatarStore {
  static final images = ValueNotifier<Map<String, Uint8List>>({});
  static String? _userId;

  static void selectUser(String userId) {
    if (_userId == userId) return;
    clear();
    _userId = userId;
  }

  static void set(String? name, String? encoded) {
    if (name == null) return;
    final updated = Map<String, Uint8List>.from(images.value);
    if (encoded == null) {
      updated.remove(name);
    } else {
      try {
        updated[name] = base64Decode(encoded);
      } on FormatException {
        updated.remove(name);
      }
    }
    images.value = updated;
  }

  static void clear() {
    _userId = null;
    images.value = {};
  }
}
