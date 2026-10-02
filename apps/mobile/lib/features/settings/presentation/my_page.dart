import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

class MyPage extends StatefulWidget {
  const MyPage(
      {required this.profile,
      required this.loadPersonalities,
      required this.savePersonality,
      required this.onEditUser,
      required this.onOpenSettings,
      this.locationEnabled = true,
      this.currentRegion,
      this.onLocationChanged,
      super.key});
  final UserProfile profile;
  final Future<ProfileOptions> Function() loadPersonalities;
  final Future<UserProfile> Function(String) savePersonality;
  final Future<UserProfile?> Function(UserProfile) onEditUser;
  final Future<void> Function() onOpenSettings;
  final bool locationEnabled;
  final String? currentRegion;
  final Future<String?> Function(bool)? onLocationChanged;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  late UserProfile _profile;
  bool _busy = false;
  bool _locationBusy = false;
  late bool _locationEnabled;
  String? _region;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _locationEnabled = widget.locationEnabled;
    _region = widget.currentRegion;
  }

  Future<void> _toggleLocation(bool enabled) async {
    setState(() => _locationBusy = true);
    try {
      final region = await widget.onLocationChanged!(enabled);
      if (mounted) {
        setState(() {
          _locationEnabled = enabled;
          _region = region;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() => _locationEnabled = enabled);
        showCenterToast(context, '地区同步暂时不可用，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
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
      final selected = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          backgroundColor: Colors.white,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('聊天性格',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700))),
                for (final personality in options.personalities)
                  ListTile(
                      title: Text(personality),
                      trailing: personality == _profile.personality
                          ? const Icon(Icons.check, color: BingoPalette.blue)
                          : null,
                      onTap: () => Navigator.pop(context, personality)),
              ])));
      if (selected == null) return;
      final result = await widget.savePersonality(selected);
      if (mounted) setState(() => _profile = result);
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
                  if (widget.onLocationChanged != null) ...[
                    const Divider(height: 1, indent: 56, endIndent: 16),
                    SwitchListTile(
                      secondary: const Icon(Icons.location_on_outlined,
                          color: BingoPalette.blue),
                      title: const Text('使用当前地区'),
                      subtitle: Text(
                          _locationBusy
                              ? '正在获取地区…'
                              : !_locationEnabled
                                  ? '已关闭，不向伙伴提供位置'
                                  : _region ?? '未获取到地区，请检查定位权限和网络',
                          style: const TextStyle(fontSize: 12)),
                      value: _locationEnabled,
                      onChanged: _locationBusy ? null : _toggleLocation,
                    ),
                  ],
                ])),
            const SizedBox(height: 18),
            if (widget.onLocationChanged != null)
              const Text('地区仅用于天气与本地信息，只保留省、市、区县，不记录具体位置。',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFF85988D), height: 1.7)),
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
