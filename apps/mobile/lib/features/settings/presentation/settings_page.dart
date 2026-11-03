import 'package:bingo/core/widgets/bingo_confirm_dialog.dart';
import 'package:flutter/services.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'dart:async';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';
import 'package:bingo/features/auth/presentation/password_recovery_page.dart';
import 'package:bingo/features/auth/presentation/user_agreement_page.dart';
import 'package:bingo/features/settings/presentation/account_deletion_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.gateway,
    required this.profile,
    required this.callCaptionsEnabled,
    required this.onCallCaptionsChanged,
    required this.onEditProfile,
    required this.onLogout,
    this.onOpenAppearance,
    this.onBack,
    this.onAccountDeleted,
    super.key,
  });

  final ServerGateway gateway;
  final UserProfile profile;
  final bool callCaptionsEnabled;
  final Future<void> Function(bool enabled) onCallCaptionsChanged;
  final Future<UserProfile?> Function(UserProfile profile) onEditProfile;
  final VoidCallback onLogout;
  final VoidCallback? onBack;
  final VoidCallback? onOpenAppearance;
  final Future<void> Function()? onAccountDeleted;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _checking = false;
  bool? _online;
  late bool _callCaptionsEnabled;
  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _callCaptionsEnabled = widget.callCaptionsEnabled;
    unawaited(_check());
  }

  Future<void> _setCallCaptionsEnabled(bool enabled) async {
    setState(() => _callCaptionsEnabled = enabled);
    try {
      await widget.onCallCaptionsChanged(enabled);
    } on Exception {
      if (mounted) setState(() => _callCaptionsEnabled = !enabled);
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final online = await widget.gateway.checkHealth();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _online = online;
    });
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showBingoConfirmDialog(context,
        title: '退出登录？',
        message: '退出后需要重新登录才能继续使用 Bingo。',
        confirmLabel: '退出登录',
        icon: Icons.logout_rounded);
    if (confirmed == true && mounted) widget.onLogout();
  }

  Future<void> _editProfile() async {
    final profile = await widget.onEditProfile(_profile);
    if (mounted && profile != null) setState(() => _profile = profile);
  }

  void _details(String title, List<Widget> rows) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => Scaffold(
              backgroundColor: BingoPalette.ice,
              appBar: AppBar(title: Text(title), centerTitle: true),
              body: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [_SettingsCard(children: rows)]))));
  Future<void> _notifications() async {
    try {
      await const MethodChannel('bingo/device_tools')
          .invokeMethod<void>('openNotificationSettings');
    } on PlatformException catch (_) {
      if (mounted) showCenterToast(context, '暂时无法打开系统通知设置');
    } on MissingPluginException catch (_) {
      if (mounted) showCenterToast(context, '请在系统设置中管理Bingo通知');
    }
  }

  void _account() => _details('账号与安全', [
        _SettingsRow(
            icon: Icons.person_outline_rounded,
            title: '昵称：${_profile.username ?? '未设置'}',
            subtitle: '手机号：${_profile.phone}'),
        if (widget.gateway is AccountGateway)
          _SettingsRow(
              icon: Icons.lock_outline_rounded,
              title: '修改密码',
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => PasswordRecoveryPage(
                      gateway: widget.gateway as AccountGateway,
                      onPasswordChanged: widget.onLogout)))),
        if (widget.gateway is AccountDeletionGateway &&
            widget.onAccountDeleted != null)
          _SettingsRow(
              icon: Icons.power_settings_new_rounded,
              title: '注销账号',
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => AccountDeletionPage(
                      gateway: widget.gateway as AccountDeletionGateway,
                      onDeleted: widget.onAccountDeleted!))))
      ]);
  void _privacy() => Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => StatefulBuilder(
          builder: (context, update) => Scaffold(
              backgroundColor: BingoPalette.ice,
              appBar: AppBar(title: const Text('隐私设置'), centerTitle: true),
              body: ListView(padding: const EdgeInsets.all(20), children: [
                _SettingsCard(children: [
                  _SettingsRow(
                      icon: Icons.closed_caption_outlined,
                      title: '通话字幕',
                      subtitle: '在通话中显示双方的实时字幕',
                      trailing: Switch.adaptive(
                          value: _callCaptionsEnabled,
                          activeTrackColor: BingoPalette.primary,
                          activeThumbColor: Colors.white,
                          onChanged: (v) async {
                            await _setCallCaptionsEnabled(v);
                            if (context.mounted) update(() {});
                          })),
                  _SettingsRow(
                      icon: Icons.shield_outlined,
                      title: '隐私政策',
                      onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                              builder: (_) => const PrivacyPolicyPage())))
                ])
              ])))));
  Widget _entry(IconData icon, String title, VoidCallback onTap,
          {String? subtitle}) =>
      _SettingsRow(
          icon: icon,
          title: title,
          subtitle: subtitle,
          onTap: onTap,
          trailing: const Icon(Icons.chevron_right_rounded,
              color: BingoPalette.muted));
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: BingoPalette.ice,
      appBar: AppBar(
          title: const Text('设置'),
          centerTitle: true,
          leading: IconButton(
              tooltip: '返回',
              onPressed:
                  widget.onBack ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left_rounded, size: 28))),
      body: ColoredBox(
          color: BingoPalette.ice,
          child: SafeArea(
              top: false,
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                  children: [
                    _SectionLabel('账号与资料'),
                    _SettingsCard(children: [
                      _entry(Icons.shield_outlined, '账号与安全', _account),
                      const _SettingsDivider(),
                      _entry(Icons.person_outline_rounded, '个人资料', _editProfile)
                    ]),
                    const SizedBox(height: 24),
                    _SectionLabel('偏好设置'),
                    _SettingsCard(children: [
                      if (widget.onOpenAppearance != null) ...[
                        _entry(Icons.palette_outlined, '聊天外观',
                            widget.onOpenAppearance!),
                        const _SettingsDivider()
                      ],
                      _entry(Icons.notifications_none_rounded, '通知设置',
                          _notifications)
                    ]),
                    const SizedBox(height: 24),
                    _SectionLabel('隐私与数据'),
                    _SettingsCard(children: [
                      _entry(Icons.lock_outline_rounded, '隐私设置', _privacy),
                      const _SettingsDivider(),
                      _entry(
                          Icons.cloud_outlined,
                          '数据与存储',
                          () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                  builder: (_) => const _StoragePage())))
                    ]),
                    const SizedBox(height: 24),
                    _SectionLabel('帮助与支持'),
                    _SettingsCard(children: [
                      _entry(
                          Icons.info_outline_rounded,
                          '关于 Bingo',
                          () => _details('关于 Bingo', [
                                const _SettingsRow(
                                    icon: Icons.info_outline_rounded,
                                    title: 'Bingo',
                                    subtitle: '版本 0.1.0'),
                                _SettingsRow(
                                    icon: Icons.check_circle_outline_rounded,
                                    title: '连接状态',
                                    subtitle:
                                        _online == true ? '服务在线' : '点击重新检查',
                                    onTap: _check)
                              ]),
                          subtitle: _online == true
                              ? '服务在线'
                              : _checking
                                  ? '正在检查连接…'
                                  : null),
                      const _SettingsDivider(),
                      _entry(
                          Icons.description_outlined,
                          '用户协议',
                          () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                  builder: (_) => const UserAgreementPage()))),
                      const _SettingsDivider(),
                      _entry(
                          Icons.shield_outlined,
                          '隐私政策',
                          () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyPage())))
                    ]),
                    const SizedBox(height: 24),
                    _SettingsCard(children: [
                      ListTile(
                          onTap: _confirmLogout,
                          title: const Text('退出登录',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: BingoPalette.rose,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)))
                    ]),
                    const SizedBox(height: 18),
                    const Center(
                        child: Text('Bingo 版本 0.1.0',
                            style: TextStyle(
                                fontSize: 10, color: BingoPalette.muted)))
                  ]))));
}

class _StoragePage extends StatefulWidget {
  const _StoragePage();
  @override
  State<_StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<_StoragePage> {
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: BingoPalette.ice,
      appBar: AppBar(title: const Text('数据与存储'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const ReferenceSurface(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('云端数据', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 9),
          Text('聊天记录、社区分享和上传的表情保存在服务器。',
              style: TextStyle(color: BingoPalette.muted, height: 1.7)),
          SizedBox(height: 20),
          Text('本机数据', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 9),
          Text('聊天外观设置、照片背景和图片缓存保存在当前设备。',
              style: TextStyle(color: BingoPalette.muted, height: 1.7))
        ])),
        const SizedBox(height: 14),
        ReferenceSurface(
            child: Column(children: [
          Text(
              '图片内存缓存：${(PaintingBinding.instance.imageCache.currentSizeBytes / 1024 / 1024).toStringAsFixed(1)} MB'),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: () {
                PaintingBinding.instance.imageCache.clear();
                setState(() {});
                showCenterToast(context, '图片内存缓存已清理');
              },
              child: const Text('清理图片内存缓存')),
          const SizedBox(height: 9),
          const Text('聊天记录、背景照片和表情不会被删除。',
              style: TextStyle(fontSize: 11, color: BingoPalette.muted))
        ]))
      ]));
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
        child: Text(
          text,
          style: const TextStyle(
            color: BingoPalette.muted,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: BingoPalette.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: BingoPalette.line),
        ),
        child: Column(children: children),
      );
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        indent: 58,
        endIndent: 20,
        color: BingoPalette.line,
      );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 3),
        minLeadingWidth: 24,
        horizontalTitleGap: 14,
        leading: Icon(icon, color: BingoPalette.ink, size: 21),
        title: Text(
          title,
          style: TextStyle(
            color: BingoPalette.ink,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: BingoPalette.muted, fontSize: 13),
              ),
        trailing: trailing,
      );
}
