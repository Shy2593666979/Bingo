import 'dart:async';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';
import 'package:bingo/features/auth/presentation/password_recovery_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.gateway,
    required this.profile,
    required this.callCaptionsEnabled,
    required this.onCallCaptionsChanged,
    required this.onEditProfile,
    required this.onLogout,
    this.onBack,
    super.key,
  });

  final ServerGateway gateway;
  final UserProfile profile;
  final bool callCaptionsEnabled;
  final Future<void> Function(bool enabled) onCallCaptionsChanged;
  final Future<UserProfile?> Function(UserProfile profile) onEditProfile;
  final VoidCallback onLogout;
  final VoidCallback? onBack;

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后需要重新登录才能继续使用 Bingo。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('退出登录',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed:
                      widget.onBack ?? () => Navigator.of(context).maybePop(),
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  '设置',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionLabel('账号'),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.person_outline_rounded,
                  title: '昵称：${_profile.username ?? '未设置'}',
                  subtitle: '手机号：${_profile.phone}',
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  icon: Icons.closed_caption_outlined,
                  title: '通话字幕',
                  subtitle:
                      _callCaptionsEnabled ? '通话中显示双方实时字幕' : '已关闭，通话时不显示字幕',
                  trailing: Transform.scale(
                    scale: 0.82,
                    alignment: Alignment.centerRight,
                    child: Switch.adaptive(
                      value: _callCaptionsEnabled,
                      activeTrackColor: const Color(0xFF8FCDB0),
                      activeThumbColor: BingoPalette.blue,
                      inactiveTrackColor: const Color(0xFFE4E8E6),
                      inactiveThumbColor: Colors.white,
                      onChanged: _setCallCaptionsEnabled,
                    ),
                  ),
                  onTap: () => _setCallCaptionsEnabled(!_callCaptionsEnabled),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionLabel('关于'),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: _online == true
                      ? Icons.check_circle_outline_rounded
                      : Icons.monitor_heart_outlined,
                  iconColor: _online == true ? const Color(0xFF3DBA89) : null,
                  title: '连接状态',
                  subtitle: switch (_online) {
                    true => '服务在线',
                    false => '服务不可用',
                    null => _checking ? '正在检查连接…' : '暂未检查连接',
                  },
                  trailing: _checking
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
                const _SettingsDivider(),
                const _SettingsRow(
                  icon: Icons.info_outline_rounded,
                  title: 'Bingo 版本',
                  subtitle: '0.1.0',
                ),
              ],
            ),
            const SizedBox(height: 28),
            if (widget.gateway is AccountGateway) ...[
              _SettingsCard(children: [
                _SettingsRow(
                    icon: Icons.lock_outline_rounded,
                    title: '修改密码',
                    subtitle: '验证当前密码后修改',
                    onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                            builder: (_) => PasswordRecoveryPage(
                                gateway: widget.gateway as AccountGateway,
                                onPasswordChanged: widget.onLogout)))),
              ]),
              const SizedBox(height: 16),
            ],
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.logout_outlined,
                  title: '退出登录',
                  iconColor: Theme.of(context).colorScheme.error,
                  titleColor: Theme.of(context).colorScheme.error,
                  onTap: _confirmLogout,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
            color: Color(0xFF60706A),
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
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE8EEEA)),
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
        color: Color(0xFFEDF1EF),
      );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.titleColor,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        minLeadingWidth: 24,
        horizontalTitleGap: 14,
        leading: Icon(icon, color: iconColor ?? BingoPalette.blue, size: 23),
        title: Text(
          title,
          style: TextStyle(
            color: titleColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF75827C), fontSize: 13),
              ),
        trailing: trailing,
      );
}
