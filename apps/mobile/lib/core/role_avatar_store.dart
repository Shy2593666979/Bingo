import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:bingo/features/chat/data/companion_store.dart';

abstract final class RoleAvatarStore {
  static final images = ValueNotifier<Map<String, Uint8List>>({});
  static final backgrounds = ValueNotifier<Map<String, int>>({});
  static const backgroundPalette = <int>[
    0xFFFBECF0, // Rose
    0xFFF6EEE7, // Cream
    0xFFEEF1E9, // Sage
    0xFFECF0F4, // Blue
    0xFFF0EDF5, // Lavender
    0xFFF8EFE8, // Peach
    0xFFEDF3EF, // Mint
    0xFFF5EDF2, // Mauve
  ];
  static const _previousPalette = <int>[
    0xFFFCE6ED,
    0xFFF5EDDC,
    0xFFEAF0E4,
    0xFFE7EFF7,
    0xFFEEE8F6,
    0xFFF8E9DF,
    0xFFE3F1ED,
    0xFFF3E7EF,
  ];
  static final _roleIds = <String, String>{};
  static final _colorsById = <String, int>{};
  static final _loadingColors = <String>{};
  static final _storage = CompanionStore();
  static int _generation = 0;
  static String? _userId;
  static final assets = <String, String>{};
  static final _encoded = <String, String?>{};
  static final _currentRoles = <String>{};

  // A fixed hash keeps first paint stable, including before disk reads finish.
  static int _defaultBackground(String identity) {
    var hash = 2166136261;
    for (final unit in identity.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xFFFFFFFF;
    }
    return backgroundPalette[hash % backgroundPalette.length];
  }

  static int backgroundFor(String? name) =>
      backgrounds.value[name] ??
      _defaultBackground(_roleIds[name] ?? name ?? '');

  static void _registerBackground(String name, String? roleId) {
    if (roleId == null || roleId.isEmpty) return;
    _roleIds[name] = roleId;
    final color =
        _colorsById.putIfAbsent(roleId, () => _defaultBackground(roleId));
    if (backgrounds.value[name] != color) {
      backgrounds.value = {...backgrounds.value, name: color};
    }
    final userId = _userId;
    if (userId != null && _loadingColors.add(roleId)) {
      _restoreBackground(userId, roleId, _generation);
    }
  }

  static Future<void> _restoreBackground(
      String userId, String roleId, int generation) async {
    try {
      final key = 'avatar_background:$roleId';
      final saved = await _storage.read(userId, key);
      if (generation != _generation || userId != _userId) return;
      // Keep previous pale colors valid if the palette changes in a later app.
      final valid = saved is int &&
          saved >= 0xFF000000 &&
          saved <= 0xFFFFFFFF &&
          ((saved >> 16) & 255) >= 200 &&
          ((saved >> 8) & 255) >= 200 &&
          (saved & 255) >= 200;
      if (valid) {
        // Keep the assigned hue; soften old saved colors to the approved set.
        final previous = _previousPalette.indexOf(saved);
        final restored = previous < 0 ? saved : backgroundPalette[previous];
        _colorsById[roleId] = restored;
        final updated = {...backgrounds.value};
        for (final entry in _roleIds.entries) {
          if (entry.value == roleId) updated[entry.key] = restored;
        }
        if (!mapEquals(updated, backgrounds.value)) backgrounds.value = updated;
        if (restored != saved) await _storage.write(userId, key, restored);
      } else {
        await _storage.write(userId, key, _colorsById[roleId]);
      }
    } catch (error) {
      // Avatar rendering remains available if local storage is unavailable.
      debugPrint('Could not restore companion avatar background: $error');
    }
  }

  static void selectUser(String userId) {
    if (_userId == userId) return;
    clear();
    _userId = userId;
  }

  static void set(String? name, String? encoded,
      {String? asset, String? roleId, bool fallback = false}) {
    if (name == null) return;
    _registerBackground(name, roleId);
    // Group membership stores a historical portrait, sometimes null. It may
    // fill an unknown role, but must never replace its current profile image.
    if (fallback && _currentRoles.contains(name)) return;
    if (!fallback) _currentRoles.add(name);
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
    _generation++;
    _userId = null;
    _roleIds.clear();
    _colorsById.clear();
    _loadingColors.clear();
    backgrounds.value = {};
    assets.clear();
    _encoded.clear();
    _currentRoles.clear();
    images.value = {};
  }
}
