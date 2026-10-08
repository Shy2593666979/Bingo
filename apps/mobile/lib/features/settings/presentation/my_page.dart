import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/presentation/companion_records_page.dart';
import 'package:bingo/shared/widgets/companion_records_icon.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

class MyPage extends StatefulWidget {
  const MyPage(
      {required this.profile,
      required this.onEditUser,
      required this.onOpenSettings,
      super.key});
  final UserProfile profile;
  final Future<UserProfile?> Function(UserProfile) onEditUser;
  final Future<void> Function() onOpenSettings;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  Future<void> _edit() async {
    final result = await widget.onEditUser(_profile);
    if (mounted && result != null) setState(() => _profile = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('我的'), centerTitle: true),
      body: DecoratedBox(
          decoration: const BoxDecoration(gradient: BingoPalette.softGradient),
          child: ListView(padding: const EdgeInsets.all(22), children: [
            const SizedBox(height: 12),
            Center(
                child:
                    UserAvatar(avatarData: _profile.userAvatarData, size: 88)),
            const SizedBox(height: 16),
            Text(_profile.username ?? 'Bingo 用户',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                '${_profile.gender ?? '未设置性别'} · ${_profile.birthday ?? '未设置生日'}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF85988D))),
            const SizedBox(height: 28),
            Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  _row(Icons.person_outline, '个人资料', '头像、昵称、性别和生日', _edit),
                  const Divider(height: 1, indent: 56, endIndent: 16),
                  _row(
                      Icons.bookmarks_outlined,
                      '陪伴记录',
                      '小记、约定、专注和入睡记录',
                      () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              CompanionRecordsPage(userId: _profile.id))),
                      leading:
                          const CompanionRecordsIcon(color: BingoPalette.blue)),
                  const Divider(height: 1, indent: 56, endIndent: 16),
                  _row(Icons.settings_rounded, '应用设置', '账号安全、通话字幕和连接状态',
                      widget.onOpenSettings),
                ])),
          ])));

  Widget _row(IconData icon, String title, String subtitle, VoidCallback? onTap,
          {Widget? leading}) =>
      ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          leading: leading ?? Icon(icon, color: BingoPalette.blue),
          title: Text(title),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF8CA397)),
          onTap: onTap);
}
