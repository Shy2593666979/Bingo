import 'dart:convert';

import 'package:bingo/core/role_avatar_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(RoleAvatarStore.clear);
  tearDown(RoleAvatarStore.clear);

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
