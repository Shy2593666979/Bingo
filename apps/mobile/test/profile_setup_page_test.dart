import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/profile_setup_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProfileGateway implements AuthGateway {
  String? savedRole;
  String? savedPersonality;

  @override
  Future<ProfileOptions> getProfileOptions() async => const ProfileOptions(
        personalities: ['温柔体贴', '活泼开朗'],
        roles: ['女朋友', '朋友'],
      );

  @override
  Future<UserProfile> updateProfile({
    required String username,
    required String assistantName,
    required String personality,
    required String role,
  }) async {
    savedRole = role;
    savedPersonality = personality;
    return UserProfile(
      id: 'user-1',
      phone: '13800138000',
      username: username,
      assistantName: assistantName,
      personality: personality,
      role: role,
      onboardingComplete: true,
    );
  }

  @override
  Future<UserProfile> getProfile() => throw UnimplementedError();
  @override
  Future<AuthResult> login(String phone, String password) =>
      throw UnimplementedError();
  @override
  Future<void> logout() => throw UnimplementedError();
  @override
  Future<AuthResult> register(String phone, String password) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('system back returns from profile editing', (tester) async {
    var cancelCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: ProfileSetupPage(
        gateway: _ProfileGateway(),
        profile: const UserProfile(
          id: 'user-1',
          phone: '13800138000',
          username: '小明',
          assistantName: 'Bingo',
          personality: '温柔体贴',
          role: '女朋友',
          onboardingComplete: true,
        ),
        onSaved: (_) {},
        onCancel: () => cancelCount += 1,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(cancelCount, 1);
  });

  testWidgets('profile setup shows compact choices and saves selections',
      (tester) async {
    final gateway = _ProfileGateway();
    UserProfile? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildBingoTheme(),
      home: ProfileSetupPage(
        gateway: gateway,
        profile: const UserProfile(
          id: 'user-1',
          phone: '13800138000',
          username: '小明',
          assistantName: 'Bingo',
          personality: '温柔体贴',
          role: '女朋友',
          onboardingComplete: true,
        ),
        onSaved: (profile) => saved = profile,
        onCancel: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('个性化设置'), findsOneWidget);
    expect(find.text('让 Bingo 更懂你'), findsOneWidget);
    expect(find.text('助手角色'), findsOneWidget);
    expect(find.text('助手性格'), findsOneWidget);
    expect(find.text('选择你希望 Bingo 扮演的角色'), findsNothing);
    expect(find.text('选择 Bingo 的性格特征，让对话更符合你的期待'), findsNothing);

    await tester.ensureVisible(find.text('助手角色'));
    await tester.tap(find.text('助手角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('朋友'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存并继续'));
    await tester.tap(find.text('保存并继续'));
    await tester.pumpAndSettle();
    expect(gateway.savedRole, '朋友');
    expect(gateway.savedPersonality, '温柔体贴');
    expect(saved?.assistantName, 'Bingo');
  });
}
