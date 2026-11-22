import 'dart:convert';
import 'dart:async';

import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(RoleAvatarStore.clear);
  tearDown(RoleAvatarStore.clear);

  group('persistent companion backgrounds', () {
    const channel = MethodChannel('bingo/local_chat');
    final disk = <String, String>{};
    final writes = <String>[];
    setUp(() {
      disk.clear();
      writes.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = '${args['user_id']}/${args['key']}';
        if (call.method == 'readCompanionData') return disk[key];
        if (call.method == 'writeCompanionData') {
          disk[key] = args['data'] as String;
          writes.add(key);
        }
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    test('new roles persist once and retain their color after a rename/restart',
        () async {
      RoleAvatarStore.selectUser('account');
      RoleAvatarStore.set('custom-name', null, roleId: 'custom-id');
      final color = RoleAvatarStore.backgroundFor('custom-name');
      for (var i = 0; i < 3; i++) {
        RoleAvatarStore.set('custom-name', null, roleId: 'custom-id');
      }
      await Future<void>.delayed(Duration.zero);
      expect(jsonDecode(disk['account/avatar_background:custom-id']!), color);
      expect(writes, hasLength(1));
      RoleAvatarStore.clear();
      RoleAvatarStore.selectUser('account');
      RoleAvatarStore.set('renamed', null, roleId: 'custom-id');
      await Future<void>.delayed(Duration.zero);
      expect(RoleAvatarStore.backgroundFor('renamed'), color);
      expect(writes, hasLength(1));
    });

    test('saved colors are restored for profiles and group snapshots',
        () async {
      disk['account/avatar_background:executive-copy'] = '${0xFFE1F1EA}';
      RoleAvatarStore.selectUser('account');
      RoleOption.fromJson({
        'id': 'executive-copy',
        'name': 'custom-name',
        'builtin': false,
      });
      GroupPerson.fromJson({
        'id': 'executive-copy',
        'name': 'nick',
        'role_name': 'group-alias',
        'active': true,
      });
      await Future<void>.delayed(Duration.zero);
      expect(RoleAvatarStore.backgroundFor('custom-name'), 0xFFE1F1EA);
      expect(RoleAvatarStore.backgroundFor('group-alias'), 0xFFE1F1EA);
      expect(writes, isEmpty);
    });

    test('previous saved hues soften once and remain stable on restart',
        () async {
      disk['account/avatar_background:role'] = '${0xFFF5EDDC}';
      RoleAvatarStore.selectUser('account');
      RoleAvatarStore.set('companion', null, roleId: 'role');
      await Future<void>.delayed(Duration.zero);
      expect(RoleAvatarStore.backgroundFor('companion'), 0xFFF6EEE7);
      expect(jsonDecode(disk['account/avatar_background:role']!), 0xFFF6EEE7);
      expect(writes, hasLength(1));
      RoleAvatarStore.clear();
      RoleAvatarStore.selectUser('account');
      RoleAvatarStore.set('companion', null, roleId: 'role');
      await Future<void>.delayed(Duration.zero);
      expect(RoleAvatarStore.backgroundFor('companion'), 0xFFF6EEE7);
      expect(writes, hasLength(1));
    });

    test('a delayed read from another account cannot repaint current avatars',
        () async {
      final pending = Completer<String?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'readCompanionData' &&
            (call.arguments as Map)['user_id'] == 'old') {
          return pending.future;
        }
        return null;
      });
      RoleAvatarStore.selectUser('old');
      RoleAvatarStore.set('same-name', null, roleId: 'old-role');
      await Future<void>.delayed(Duration.zero);
      RoleAvatarStore.selectUser('new');
      RoleAvatarStore.set('same-name', null, roleId: 'new-role');
      final current = RoleAvatarStore.backgroundFor('same-name');
      pending.complete('${0xFFE1F1EA}');
      await Future<void>.delayed(Duration.zero);
      expect(RoleAvatarStore.backgrounds.value.keys, ['same-name']);
      expect(current, isIn(RoleAvatarStore.backgroundPalette));
      expect(RoleAvatarStore.backgroundFor('same-name'), current);
    });
  });

  test(
      'group snapshots cannot replace the current companion portrait on refresh',
      () {
    final current = base64Encode([1, 2, 3]);
    final previous = base64Encode([4, 5, 6]);
    final role = {
      'id': 'executive-copy',
      'name': '余承东',
      'builtin': false,
      'avatar_data': current,
      'avatar_asset': 'executive.png',
    };
    RoleOption.fromJson(role);
    final bytes = RoleAvatarStore.images.value['余承东'];
    var changes = 0;
    void changed() => changes++;
    RoleAvatarStore.images.addListener(changed);
    addTearDown(() => RoleAvatarStore.images.removeListener(changed));
    for (var index = 0; index < 3; index++) {
      RoleOption.fromJson(role);
      for (final snapshot in [previous, null]) {
        GroupPerson.fromJson({
          'id': 'executive-copy',
          'name': '余承东',
          'role_name': '余承东',
          'active': true,
          'avatar_asset': 'executive.png',
          'avatar_data': snapshot,
        });
        expect(identical(RoleAvatarStore.images.value['余承东'], bytes), isTrue);
      }
    }
    expect(changes, 0);
  });

  test('refreshing unchanged uploaded portraits reuses decoded image bytes',
      () {
    final first = base64Encode([1, 2, 3]);
    RoleAvatarStore.set('社区搭子', first, asset: 'assets/images/executive.png');
    final bytes = RoleAvatarStore.images.value['社区搭子'];
    var changes = 0;
    void changed() => changes++;
    RoleAvatarStore.images.addListener(changed);
    addTearDown(() => RoleAvatarStore.images.removeListener(changed));
    for (var index = 0; index < 5; index++) {
      RoleAvatarStore.set('社区搭子', first, asset: 'assets/images/executive.png');
    }
    expect(changes, 0);
    expect(identical(RoleAvatarStore.images.value['社区搭子'], bytes), isTrue);
    RoleAvatarStore.set('社区搭子', base64Encode([4, 5, 6]));
    expect(changes, 1);
    expect(RoleAvatarStore.images.value['社区搭子'], [4, 5, 6]);
    RoleAvatarStore.set('社区搭子', null);
    expect(RoleAvatarStore.images.value.containsKey('社区搭子'), isFalse);
  });

  test('group-only portraits work until a current profile arrives', () {
    final snapshot = base64Encode([4, 5, 6]);
    final current = base64Encode([1, 2, 3]);
    RoleAvatarStore.selectUser('first-account');
    RoleAvatarStore.set('群成员', snapshot, fallback: true);
    expect(RoleAvatarStore.images.value['群成员'], [4, 5, 6]);
    RoleAvatarStore.set('群成员', current);
    RoleAvatarStore.set('群成员', snapshot, fallback: true);
    expect(RoleAvatarStore.images.value['群成员'], [1, 2, 3]);
    RoleAvatarStore.set('群成员', null);
    RoleAvatarStore.set('群成员', snapshot, fallback: true);
    expect(RoleAvatarStore.images.value.containsKey('群成员'), isFalse);
    RoleAvatarStore.selectUser('second-account');
    RoleAvatarStore.set('群成员', snapshot, fallback: true);
    expect(RoleAvatarStore.images.value['群成员'], [4, 5, 6]);
  });

  test('asset changes update listeners and account switch clears image cache',
      () {
    RoleAvatarStore.selectUser('one');
    final encoded = base64Encode([1, 2, 3]);
    RoleAvatarStore.set('同名搭子', encoded, asset: 'old.png');
    final bytes = RoleAvatarStore.images.value['同名搭子'];
    RoleAvatarStore.set('同名搭子', encoded, asset: 'new.png');
    expect(RoleAvatarStore.assets['同名搭子'], 'new.png');
    expect(identical(RoleAvatarStore.images.value['同名搭子'], bytes), isTrue);
    RoleAvatarStore.selectUser('two');
    expect(RoleAvatarStore.images.value, isEmpty);
    expect(RoleAvatarStore.assets, isEmpty);
    RoleAvatarStore.set('同名搭子', encoded);
    expect(RoleAvatarStore.images.value['同名搭子'], [1, 2, 3]);
    expect(identical(RoleAvatarStore.images.value['同名搭子'], bytes), isFalse);
  });
}
