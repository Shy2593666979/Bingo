import 'package:bingo/core/design/approved_art.dart';
import 'package:bingo/core/design/pearl_icon.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/design/companion_launch_ui.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';

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
  List<RoleOption> _roles = [];
  List<ChatGroup> _groups = [];
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final roles = await widget.roles.listRoles();
      final groups = await widget.groups.listGroups();
      if (mounted) {
        setState(() {
          _roles = roles;
          _groups = groups;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Widget _menu(IconData icon, String title, VoidCallback onTap,
          {String? subtitle, String? value, bool last = false}) =>
      InkWell(
          onTap: onTap,
          child: Column(children: [
            ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: subtitle == null ? 54 : 78),
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    child: Row(children: [
                      ApprovedMenuIcon(switch (icon) {
                        Icons.person_outline_rounded => 0,
                        Icons.mic_none_rounded => 1,
                        Icons.share_outlined => 2,
                        Icons.favorite_border_rounded => 3,
                        Icons.palette_outlined => 4,
                        _ => 5
                      }),
                      const SizedBox(width: 16),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(title,
                                style: BingoTypography.menuTitle.copyWith(
                                    fontSize: 18, fontWeight: FontWeight.w600)),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(subtitle,
                                  style: CompanionLaunch.text(14,
                                      color: const Color(0xFF666666))),
                            ],
                          ])),
                      if (value != null) ...[
                        const SizedBox(width: 8),
                        Text(value,
                            style: CompanionLaunch.text(12,
                                color: CompanionLaunch.muted)),
                      ],
                      const SizedBox(width: 12),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: BingoPalette.muted),
                    ]))),
            if (!last)
              const Divider(height: 1, indent: 48, color: BingoPalette.line),
          ]));

  Widget _welcome() => InkWell(
      onTap: widget.onManageRoles ?? widget.onPartners,
      borderRadius: BorderRadius.circular(16),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
              color: const Color(0xFFF7F6F5),
              borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const PearlIcon(PearlSymbol.group, size: 25),
            const SizedBox(width: 18),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('我的陪伴',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${_roles.length} 位搭子，随时都在',
                      style: const TextStyle(
                          fontSize: 13, color: BingoPalette.muted))
                ]))
          ])));
  @override
  Widget build(BuildContext context) => ColoredBox(
      color: BingoPalette.pageBottom,
      child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  children: [
                    Padding(
                        padding: const EdgeInsets.only(top: 40, bottom: 26),
                        child: Row(children: [
                          InkWell(
                              onTap: widget.onEdit,
                              child: ClipOval(
                                  child: UserAvatar(
                                      avatarData: widget.profile.userAvatarData,
                                      username: widget.profile.username ?? '',
                                      size: 76))),
                          const SizedBox(width: 14),
                          Flexible(
                              child: InkWell(
                                  onTap: widget.onEdit,
                                  child: Text(
                                      widget.profile.username ?? 'Bingo 用户',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: CompanionLaunch.text(20,
                                          weight: FontWeight.w600)))),
                          const SizedBox(width: 6),
                          PopupMenuButton<int>(
                              tooltip: '编辑个人资料',
                              icon: const Icon(Icons.edit_rounded,
                                  size: 17, color: BingoPalette.muted),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 36),
                              onSelected: (v) {
                                if (v == 0) {
                                  widget.onEdit();
                                } else if (v == 1) {
                                  widget.onFavorites();
                                } else {
                                  (widget.onGroups ??
                                      () => _showGroups(context))();
                                }
                              },
                              itemBuilder: (_) => [
                                    const PopupMenuItem(
                                        value: 0, child: Text('编辑个人资料')),
                                    const PopupMenuItem(
                                        value: 2, child: Text('我的群聊'))
                                  ]),
                        ])),
                    _welcome(),
                    const SizedBox(height: 20),
                    if (_failed)
                      TextButton(
                          onPressed: refresh,
                          child: const Text('部分信息加载失败，点击重试')),
                    Container(
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.transparent)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          _menu(Icons.person_outline_rounded, '我的搭子',
                              widget.onManageRoles ?? widget.onPartners,
                              value: null),
                          if (widget.onVoices != null)
                            _menu(Icons.mic_none_rounded, '我的音色',
                                widget.onVoices!),
                          _menu(Icons.share_outlined, '我的分享', widget.onShares,
                              value: null),
                          _menu(Icons.favorite_border_rounded, '我的收藏',
                              widget.onFavorites),
                          _menu(Icons.palette_outlined, '聊天外观',
                              widget.onAppearance ?? widget.onSettings),
                          _menu(
                              Icons.settings_outlined, '设置', widget.onSettings,
                              last: true),
                        ])),
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
