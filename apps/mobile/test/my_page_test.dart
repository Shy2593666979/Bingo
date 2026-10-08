import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/settings/presentation/my_page.dart';
import 'package:bingo/shared/widgets/companion_records_icon.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'my page keeps user details, records and settings without personality',
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
    var userEdited = false;
    var settingsOpened = false;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: MyPage(
            profile: profile,
            onEditUser: (_) async {
              userEdited = true;
              return null;
            },
            onOpenSettings: () async => settingsOpened = true)));
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('陪伴记录'), findsOneWidget);
    expect(find.byType(CompanionRecordsIcon), findsOneWidget);
    expect(find.byIcon(Icons.bookmarks_outlined), findsNothing);
    expect(find.text('使用当前地区'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    expect(find.text('小雨'), findsOneWidget);
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.text('甜甜'), findsNothing);
    expect(find.text('聊天性格'), findsNothing);
    expect(find.textContaining('这里设置默认聊天性格'), findsNothing);
    await tester.tap(find.text('个人资料'));
    await tester.pumpAndSettle();
    expect(userEdited, isTrue);
    await tester.tap(find.text('应用设置'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
