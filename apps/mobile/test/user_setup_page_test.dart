import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/user_setup_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const profile = UserProfile(
    id: 'user',
    phone: '13800002222',
    username: null,
    assistantName: null,
    personality: null,
    role: null,
    onboardingComplete: false);

class DetailsGateway implements UserDetailsGateway {
  String? nickname;
  String? gender;
  DateTime? birthday;
  String? avatar;

  @override
  Future<UserDetailsResult> saveUserDetails(
      {required String nickname,
      required String gender,
      required DateTime birthday,
      String? avatarData}) async {
    this.nickname = nickname;
    this.gender = gender;
    this.birthday = birthday;
    avatar = avatarData;
    return const UserDetailsResult(profile, null);
  }
}

void main() {
  testWidgets('first login only asks for user details with a birthday wheel',
      (tester) async {
    final gateway = DetailsGateway();
    UserProfile? saved;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: UserSetupPage(
            gateway: gateway,
            profile: profile,
            onSaved: (value) => saved = value)));
    expect(find.text('用户昵称'), findsOneWidget);
    expect(find.text('用户性别'), findsOneWidget);
    expect(find.text('用户生日'), findsOneWidget);
    expect(find.text('助手名称'), findsNothing);
    expect(find.text('助手角色'), findsNothing);
    expect(find.text('助手性格'), findsNothing);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
        (image.image as AssetImage).assetName, 'assets/images/bingo_logo.png');
    await tester.enterText(find.byType(TextFormField), '小雨');
    await tester.pumpAndSettle();
    final nicknameCard = find.ancestor(
        of: find.byType(TextFormField),
        matching: find.byWidgetPredicate((widget) =>
            widget is Material && widget.clipBehavior == Clip.antiAlias));
    final labelBounds = tester.getRect(find.text('用户昵称'));
    final cardBounds = tester.getRect(nicknameCard.first);
    expect(labelBounds.top, greaterThanOrEqualTo(cardBounds.top));
    expect(labelBounds.bottom, lessThanOrEqualTo(cardBounds.bottom));
    tester.testTextInput.hide();
    await tester.tap(find.text('女'));
    await tester.ensureVisible(find.text('用户生日'));
    await tester.tap(find.text('用户生日'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('完成，开始体验'));
    await tester.tap(find.text('完成，开始体验'));
    await tester.pumpAndSettle();
    expect(gateway.nickname, '小雨');
    expect(gateway.gender, '女');
    expect(gateway.birthday, DateTime(2000, 1, 1));
    expect(gateway.avatar, isNull);
    expect(saved, profile);
    expect(tester.takeException(), isNull);
  });
}
