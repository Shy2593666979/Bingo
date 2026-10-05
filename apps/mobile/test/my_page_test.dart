import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/settings/presentation/my_page.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('my page separates user details, personality and app settings',
      (tester) async {
    const profile = UserProfile(
        id: 'user',
        phone: '13800001111',
        username: '小雨',
        assistantName: '甜甜',
        personality: '温柔体贴',
        role: '女朋友',
        onboardingComplete: true,
        birthday: '2000-01-01',
        gender: '女');
    String? saved;
    var settingsOpened = false;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: MyPage(
            profile: profile,
            loadPersonalities: () async => const ProfileOptions(
                personalities: ['温柔体贴', '幽默风趣'], roles: []),
            savePersonality: (value) async {
              saved = value;
              return profile;
            },
            onEditUser: (_) async => null,
            onOpenSettings: () async => settingsOpened = true)));
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('使用当前地区'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    expect(find.text('小雨'), findsOneWidget);
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.text('甜甜'), findsNothing);
    await tester.tap(find.text('聊天性格'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('幽默风趣'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('你喜欢怎样的回应？'), findsOneWidget);
    await tester.tap(find.text('保存性格'));
    await tester.pumpAndSettle();
    expect(saved, '幽默风趣');
    await tester.tap(find.text('应用设置'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
