import 'package:bingo/features/roles/data/local_role_order_store.dart';

class MemoryRoleOrderStore implements LocalRoleOrderStore {
  final Map<String, List<String>> orders = {};

  @override
  Future<List<String>> load(String userId) async =>
      List.of(orders[userId] ?? []);

  @override
  Future<void> save(String userId, List<String> roleIds) async {
    orders[userId] = List.of(roleIds);
  }
}
