import 'package:bingo/core/config/app_config.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.gateway,
    required this.config,
    required this.profile,
    required this.callCaptionsEnabled,
    required this.onCallCaptionsChanged,
    required this.onEditProfile,
    required this.onLogout,
    super.key,
  });

  final ServerGateway gateway;
  final AppConfig config;
  final UserProfile profile;
  final bool callCaptionsEnabled;
  final Future<void> Function(bool enabled) onCallCaptionsChanged;
  final VoidCallback onEditProfile;
  final VoidCallback onLogout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _checking = false;
  bool? _online;
  late bool _callCaptionsEnabled;

  @override
  void initState() {
    super.initState();
    _callCaptionsEnabled = widget.callCaptionsEnabled;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BingoPalette.softGradient),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: '返回',
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '设置',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: BingoPalette.brandGradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x303478F6),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    AssistantAvatar(role: widget.profile.role, size: 66),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.profile.assistantName ?? 'Bingo',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.profile.role ?? '未设置'} · ${widget.profile.personality ?? '未设置'}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      onPressed: widget.onEditProfile,
                      tooltip: '编辑助手',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.edit_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SectionLabel('账号'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.person_rounded,
                    title: widget.profile.username ?? widget.profile.phone,
                    subtitle: widget.profile.phone,
                  ),
                  const _SoftDivider(),
                  _SettingsRow(
                    icon: Icons.logout_rounded,
                    title: '退出登录',
                    titleColor: Theme.of(context).colorScheme.error,
                    onTap: widget.onLogout,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _SectionLabel('通话'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.closed_caption_rounded,
                    title: '通话字幕',
                    subtitle:
                        _callCaptionsEnabled ? '通话中显示双方实时字幕' : '已关闭，通话时不显示字幕',
                    trailing: Switch.adaptive(
                      value: _callCaptionsEnabled,
                      onChanged: (enabled) => _setCallCaptionsEnabled(enabled),
                    ),
                    onTap: () => _setCallCaptionsEnabled(!_callCaptionsEnabled),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _SectionLabel('连接'),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.cloud_rounded,
                    title: '服务端地址',
                    subtitle: widget.config.apiBaseUri.toString(),
                  ),
                  const _SoftDivider(),
                  _SettingsRow(
                    icon: _online == true
                        ? Icons.check_circle_rounded
                        : Icons.monitor_heart_rounded,
                    iconColor: _online == true ? const Color(0xFF3DBA89) : null,
                    title: '连接状态',
                    subtitle: switch (_online) {
                      true => '服务在线',
                      false => '服务不可用',
                      null => '点击检测当前连接',
                    },
                    trailing: _checking
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    onTap: _checking ? null : _check,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _SectionLabel('关于'),
              const _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: Icons.shield_rounded,
                    title: '本地网络传输',
                    subtitle: 'HTTP REST · 数据由你的服务端处理',
                  ),
                  _SoftDivider(),
                  _SettingsRow(
                    icon: Icons.info_rounded,
                    title: 'Bingo 版本',
                    subtitle: '0.1.0',
                  ),
                ],
              ),
            ],
          ),
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
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF747D99),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D263C72),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(children: children),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF4FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor ?? BingoPalette.blue, size: 21),
        ),
        title: Text(
          title,
          style: TextStyle(color: titleColor, fontWeight: FontWeight.w700),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF7A829B)),
              ),
        trailing: trailing,
      );
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: 70),
        child: Divider(height: 1, color: BingoPalette.line),
      );
}
