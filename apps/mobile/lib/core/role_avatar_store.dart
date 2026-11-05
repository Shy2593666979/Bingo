import 'dart:convert';

import 'package:flutter/foundation.dart';

abstract final class RoleAvatarStore {
  static final images = ValueNotifier<Map<String, Uint8List>>({});
  static String? _userId;
  static final assets = <String, String>{};
  static final _encoded = <String, String?>{};

  static void selectUser(String userId) {
    if (_userId == userId) return;
    clear();
    _userId = userId;
  }

  static void set(String? name, String? encoded, {String? asset}) {
    if (name == null) return;
    final assetChanged = asset != null && assets[name] != asset;
    if (asset != null) assets[name] = asset;
    if (_encoded.containsKey(name) && _encoded[name] == encoded) {
      if (assetChanged) images.value = Map.of(images.value);
      return;
    }
    _encoded[name] = encoded;
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
    assets.clear();
    _encoded.clear();
    images.value = {};
  }
}
