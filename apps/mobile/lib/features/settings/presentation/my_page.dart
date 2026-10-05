import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:bingo/features/settings/presentation/personality_page.dart';
import 'package:flutter/material.dart';

class MyPage extends StatefulWidget {
  const MyPage(
      {required this.profile,
      required this.loadPersonalities,
      required this.savePersonality,
      required this.onEditUser,
      required this.onOpenSettings,
      super.key});
  final UserProfile profile;
  final Future<ProfileOptions> Function() loadPersonalities;
  final Future<UserProfile> Function(String) savePersonality;
  final Future<UserProfile?> Function(UserProfile) onEditUser;
  final Future<void> Function() onOpenSettings;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  late UserProfile _profile;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  Future<void> _edit() async {
    final result = await widget.onEditUser(_profile);
    if (mounted && result != null) setState(() => _profile = result);
  }

  Future<void> _personality() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final options = await widget.loadPersonalities();
      if (!mounted) return;
      final result = await Navigator.of(context).push<UserProfile>(
          MaterialPageRoute(
              builder: (_) => PersonalityPage(
                  options: options.personalities,
                  selected: _profile.personality,
                  save: widget.savePersonality)));
      if (mounted && result != null) setState(() => _profile = result);
    } on ApiException catch (error) {
      if (mounted) showCenterToast(context, error.message);
    } on Exception {
      if (mounted) showCenterToast(context, '暂时无法更新性格，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                      Icons.sentiment_satisfied_alt_outlined,
                      '聊天性格',
                      _busy ? '正在更新…' : _profile.personality ?? '温柔体贴',
                      _busy ? null : _personality),
                  const Divider(height: 1, indent: 56, endIndent: 16),
                  _row(Icons.settings_rounded, '应用设置', '账号安全、通话字幕和连接状态',
                      widget.onOpenSettings),
                ])),
            const SizedBox(height: 18),
            const Text('这里设置默认聊天性格，也可以在编辑伙伴时为每位伙伴单独设置。',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF85988D), height: 1.7)),
          ])));

  Widget _row(
          IconData icon, String title, String subtitle, VoidCallback? onTap) =>
      ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          leading: Icon(icon, color: BingoPalette.blue),
          title: Text(title),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF8CA397)),
          onTap: onTap);
}
