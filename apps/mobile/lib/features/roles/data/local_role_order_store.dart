import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:flutter/services.dart';

abstract interface class LocalRoleOrderStore {
  Future<List<String>> load(String userId);
  Future<void> save(String userId, List<String> roleIds);
}

class AndroidLocalRoleOrderStore implements LocalRoleOrderStore {
  const AndroidLocalRoleOrderStore();
  static const _channel = MethodChannel('bingo/local_chat');

  @override
  Future<List<String>> load(String userId) async =>
      await _channel
          .invokeListMethod<String>('loadRoleOrder', {'user_id': userId}) ??
      [];

  @override
  Future<void> save(String userId, List<String> roleIds) =>
      _channel.invokeMethod<void>(
          'saveRoleOrder', {'user_id': userId, 'role_ids': roleIds});
}

List<RoleOption> applyLocalRoleOrder(
    List<RoleOption> roles, List<String> roleIds) {
  final remaining = {for (final role in roles) role.id: role};
  final ordered = <RoleOption>[];
  for (final roleId in roleIds) {
    final role = remaining.remove(roleId);
    if (role != null) ordered.add(role);
  }
  ordered.addAll(remaining.values);
  return ordered;
}
