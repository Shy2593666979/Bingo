import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

import 'package:bingo/features/settings/presentation/profile_menu_icon.dart';

class ReferenceMyPage extends StatefulWidget {
  const ReferenceMyPage(
      {required this.profile,
      required this.roles,
      required this.groups,
      required this.community,
      required this.onEdit,
      required this.onSettings,
      required this.onShares,
      required this.onFavorites,
      required this.onRole,
      required this.onGroup,
      required this.onShare,
      required this.onCreate,
      required this.onPartners,
      this.onMessages,
      this.onGroups,
      this.onAppearance,
      this.onVoices,
      this.onManageRoles,
      super.key});
  final UserProfile profile;
  final RoleGateway roles;
  final GroupGateway groups;
  final CommunityGateway community;
  final Future<void> Function() onEdit, onSettings, onCreate;
  final Future<void> Function()? onAppearance;
  final VoidCallback onShares, onFavorites, onPartners;
  final VoidCallback? onMessages;
  final VoidCallback? onGroups;
  final VoidCallback? onVoices, onManageRoles;
  final Future<void> Function(String) onRole, onShare;
  final Future<void> Function(ChatGroup) onGroup;
  @override
  State<ReferenceMyPage> createState() => ReferenceMyPageState();
}

class ReferenceMyPageState extends State<ReferenceMyPage> {
  List<ChatGroup> _groups = [];
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final groups = await widget.groups.listGroups();
      if (mounted) {
        setState(() {
          _groups = groups;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  static const _pageColor = Color(0xFFFBFBFD);
  static const _sectionLine = Color(0xFFDCE0E8);
  static const _rowLine = Color(0xFFEDEDF0);

  Widget _menu(ProfileMenuSymbol symbol, String title, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 55),
          child: Row(children: [
            SizedBox(
              width: 48,
              child: Center(
                child: ProfileMenuIcon(symbol),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 55),
                decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _rowLine))),
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(title,
                          style: BingoTypography.menuTitle.copyWith(
                              fontSize: 20,
                              height: 1.4,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 22, color: Color(0xFF8B8F96)),
                ]),
              ),
            ),
          ]),
        ),
      );

  Widget _section(String title, List<Widget> rows, {bool settings = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Divider(height: 2, thickness: 2, color: _sectionLine)),
        Container(
          constraints: BoxConstraints(minHeight: settings ? 61 : 55),
          padding: EdgeInsets.fromLTRB(16, settings ? 0 : 4, 14, 0),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
            Color(0xFFF8F9FB),
            Color(0xFFF5F6F8),
            Color(0xFFFAFBFC),
          ], stops: [
            0,
            .68,
            1
          ])),
          child: Text(title,
              style: BingoTypography.sectionTitle.copyWith(
                  fontSize: 24,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF152033))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(children: rows),
        ),
      ]);

  Widget _profile() {
    final username = widget.profile.username?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: InkWell(
        onTap: widget.onEdit,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 121),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(1, 17, 1, 26),
            child: Row(children: [
              UserAvatar(
                avatarData: widget.profile.userAvatarData,
                username: username?.isNotEmpty == true ? username! : '',
                size: 70,
                initialTextStyle:
                    const TextStyle(fontSize: 38, fontWeight: FontWeight.w400),
              ),
              const SizedBox(width: 25),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          username?.isNotEmpty == true ? username! : 'Bingo 用户',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: BingoTypography.profileName.copyWith(
                              fontSize: 24,
                              height: 1.3,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Text('我的AI陪伴空间',
                          style: BingoTypography.secondary.copyWith(
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF515A68))),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 21, color: Color(0xFF7B8189)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: _pageColor,
      child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 26),
                  children: [
                    _profile(),
                    if (_failed)
                      TextButton(
                          onPressed: refresh,
                          child: const Text('部分信息加载失败，点击重试')),
                    _section('我的内容', [
                      _menu(ProfileMenuSymbol.me, '我的搭子',
                          widget.onManageRoles ?? widget.onPartners),
                      _menu(ProfileMenuSymbol.group, '我的群聊',
                          widget.onGroups ?? () => _showGroups(context)),
                      if (widget.onVoices != null)
                        _menu(ProfileMenuSymbol.waveform, '我的音色',
                            widget.onVoices!),
                      _menu(ProfileMenuSymbol.share, '我的分享', widget.onShares),
                      _menu(ProfileMenuSymbol.star, '我的收藏', widget.onFavorites),
                    ]),
                    const SizedBox(height: 20),
                    _section(
                        '应用设置',
                        [
                          _menu(ProfileMenuSymbol.shirt, '外观设置',
                              widget.onAppearance ?? widget.onSettings),
                          _menu(ProfileMenuSymbol.settings, '设置',
                              widget.onSettings),
                        ],
                        settings: true),
                  ]))));

  void _showGroups(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
            const ListTile(
                title: Text('我的群聊',
                    style: TextStyle(fontWeight: FontWeight.w500))),
            if (_groups.isEmpty) const ListTile(title: Text('还没有群聊，可在创建中心创建')),
            for (final group in _groups)
              ListTile(
                  title: Text(group.name),
                  subtitle: Text('${group.activeMembers.length}位搭子'),
                  onTap: () {
                    Navigator.pop(sheet);
                    widget.onGroup(group);
                  })
          ])));
}
