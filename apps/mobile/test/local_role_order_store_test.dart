import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/roles/data/local_role_order_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const roles = [
    RoleOption(id: 'first', name: '第一位', builtin: true),
    RoleOption(id: 'second', name: '第二位', builtin: true),
    RoleOption(id: 'new', name: '新伙伴', builtin: false),
  ];

  test('no local order preserves the server default', () {
    expect(applyLocalRoleOrder(roles, []).map((role) => role.id),
        ['first', 'second', 'new']);
  });

  test('deleted and duplicate IDs are ignored and new partners append', () {
    expect(
        applyLocalRoleOrder(roles, ['deleted', 'second', 'second', 'first'])
            .map((role) => role.id),
        ['second', 'first', 'new']);
  });

  test('native storage sends account-scoped IDs through the local channel',
      () async {
    const channel = MethodChannel('bingo/local_chat');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'loadRoleOrder' ? ['second', 'first'] : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const store = AndroidLocalRoleOrderStore();
    expect(await store.load('account-a'), ['second', 'first']);
    await store.save('account-a', ['first', 'second']);
    expect(calls[0].arguments, {'user_id': 'account-a'});
    expect(calls[1].method, 'saveRoleOrder');
    expect(calls[1].arguments, {
      'user_id': 'account-a',
      'role_ids': ['first', 'second']
    });
  });
}
