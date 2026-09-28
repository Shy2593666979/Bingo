import 'package:bingo/app.dart';
import 'package:bingo/features/auth/data/auth_token_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class EmptyTokenStore implements TokenStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}
}

void main() {
  testWidgets('shows splash before authentication', (tester) async {
    await tester.pumpWidget(BingoApp(tokenStore: EmptyTokenStore()));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('你的个人智能助理'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('创建 Bingo 账号'), findsOneWidget);
    expect(find.text('手机号'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
  });
}
