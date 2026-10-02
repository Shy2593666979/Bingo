import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/roles/presentation/role_home_page.dart';
import 'package:bingo/features/roles/role_traits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/memory_role_order_store.dart';

class _Gateway implements RoleGateway {
  @override
  Future<List<RoleOption>> listRoles() async => const [
        RoleOption(
            id: 'girlfriend',
            name: '女朋友',
            builtin: true,
            categories: ['陪伴', '恋人'],
            traits: ['温柔体贴', '主动关心'],
            messageCount: 12),
        RoleOption(
            id: 'teacher',
            name: '老师',
            builtin: true,
            categories: ['陪伴', '成长'],
            traits: ['耐心讲解', '答疑解惑']),
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('role page keeps traits without search or category controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RoleHomePage(
                userId: 'test-user',
                orderStore: MemoryRoleOrderStore(),
                gateway: _Gateway(),
                onOpenRole: (_) async {}))));
    await tester.pumpAndSettle();
    expect(find.text('女朋友'), findsOneWidget);
    expect(find.byType(TraitIcon), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('全部'), findsNothing);
    expect(find.text('恋人'), findsNothing);
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    expect(find.byTooltip('我的'), findsOneWidget);
    expect(find.text('老师'), findsOneWidget);
    expect(find.text('女朋友'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
