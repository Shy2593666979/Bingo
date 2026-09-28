import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _HealthyServer implements ServerGateway {
  @override
  Future<bool> checkHealth() async => true;
}

void main() {
  testWidgets('settings keeps account details and separates logout',
      (tester) async {
    var logoutCount = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildBingoTheme(),
      home: SettingsPage(
        gateway: _HealthyServer(),
        profile: const UserProfile(
          id: 'user-1',
          phone: '13800138000',
          username: '小明',
          assistantName: 'Bingo',
          personality: '温柔体贴',
          role: '女朋友',
          onboardingComplete: true,
        ),
        callCaptionsEnabled: false,
        onCallCaptionsChanged: (_) async {},
        onEditProfile: () {},
        onLogout: () => logoutCount++,
      ),
    ));

    expect(find.text('昵称：小明'), findsOneWidget);
    expect(find.text('手机号：13800138000'), findsOneWidget);
    expect(find.text('服务端地址'), findsNothing);
    expect(find.text('本地网络传输'), findsNothing);

    await tester.scrollUntilVisible(find.text('退出登录'), 200);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(logoutCount, 0);
    expect(find.text('退出登录？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(logoutCount, 0);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '退出登录'));
    await tester.pumpAndSettle();
    expect(logoutCount, 1);
  });
}
