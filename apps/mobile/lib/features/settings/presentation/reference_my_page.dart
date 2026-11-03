import 'package:bingo/core/design/release_ui.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/core/design/bingo_surface.dart';
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
      super.key});
  final UserProfile profile;
  final RoleGateway roles;
  final GroupGateway groups;
  final CommunityGateway community;
  final Future<void> Function() onEdit, onSettings, onCreate;
  final VoidCallback onShares, onFavorites, onPartners;
  final VoidCallback? onMessages;
  final VoidCallback? onGroups;
  final Future<void> Function(String) onRole, onShare;
  final Future<void> Function(ChatGroup) onGroup;
  @override
  State<ReferenceMyPage> createState() => ReferenceMyPageState();
}

class ReferenceMyPageState extends State<ReferenceMyPage> {
  List<RoleOption> _roles = [];
  List<ChatGroup> _groups = [];
  List<CommunityShare> _shares = [];
  int _favorites = 0;
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
      final shares = await widget.community.listCommunity(scope: 'mine');
      final favorites =
          await widget.community.listCommunity(scope: 'favorites');
      if (mounted) {
        setState(() {
          _roles = roles;
          _groups = groups;
          _shares = shares.items;
          _favorites = favorites.total ?? favorites.items.length;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Widget _heading(String title, int count, VoidCallback tap) => Row(children: [
        Expanded(
            child: Row(children: [
          Flexible(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600))),
          const SizedBox(width: 7),
          Text('$count',
              style: const TextStyle(fontSize: 12, color: BingoPalette.muted)),
        ])),
        TextButton(
            onPressed: tap,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(44, 40),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                foregroundColor: BingoPalette.muted),
            child: const Text('全部 ›', style: TextStyle(fontSize: 12))),
      ]);

  Widget _stat(String label, int count, VoidCallback onTap) => Expanded(
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(children: [
                Text('$count',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(label,
                    style: const TextStyle(fontSize: 12, color: refMuted)),
              ]))));

  Widget _menuRow(IconData icon, String title, VoidCallback onTap,
          {int? count}) =>
      ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          minLeadingWidth: 20,
          horizontalTitleGap: 14,
          leading: Icon(icon, size: 20, color: BingoPalette.primary),
          title: Text(title, style: const TextStyle(fontSize: 13)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (count != null) ...[
              Text('$count',
                  style: const TextStyle(fontSize: 12, color: refMuted)),
              const SizedBox(width: 8)
            ],
            const Icon(Icons.chevron_right_rounded, size: 20, color: refMuted),
          ]),
          onTap: onTap);

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: BingoPalette.ice,
      child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: [
                    ReleasePageHeader('我的', eyebrow: '属于你的陪伴空间', actions: [
                      IconButton(
                          tooltip: '设置',
                          onPressed: widget.onSettings,
                          icon: const Icon(Icons.settings_outlined, size: 23)),
                    ]),
                    const SizedBox(height: 12),
                    BingoSurface(
                        radius: 15,
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        child: Column(children: [
                          InkWell(
                              onTap: widget.onEdit,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(children: [
                                    UserAvatar(
                                        avatarData:
                                            widget.profile.userAvatarData,
                                        username: widget.profile.username ?? '',
                                        size: 56),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(
                                              widget.profile.username ??
                                                  'Bingo 用户',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 21,
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 6),
                                          const Text('记录每一份陪伴',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: refMuted)),
                                        ])),
                                    const SizedBox(width: 6),
                                    const Text('编辑资料 ›',
                                        style: TextStyle(
                                            fontSize: 11, color: refMuted)),
                                  ]))),
                          const SizedBox(height: 18),
                          const Divider(height: 1, color: BingoPalette.line),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(children: [
                                _stat('搭子', _roles.length, widget.onPartners),
                                const SizedBox(
                                    height: 30,
                                    child: VerticalDivider(
                                        color: BingoPalette.line)),
                                _stat('分享', _shares.length, widget.onShares),
                                const SizedBox(
                                    height: 30,
                                    child: VerticalDivider(
                                        color: BingoPalette.line)),
                                _stat(
                                    '群聊',
                                    _groups.length,
                                    widget.onGroups ??
                                        () => _showGroups(context)),
                              ])),
                        ])),
                    if (_failed)
                      TextButton(
                          onPressed: refresh,
                          child: const Text('部分信息加载失败，点击重试')),
                    const SizedBox(height: 14),
                    BingoSurface(
                        radius: 15,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                        child: Column(children: [
                          _heading('我的搭子', _roles.length, widget.onPartners),
                          const SizedBox(height: 6),
                          SizedBox(
                              height: 60 +
                                  MediaQuery.textScalerOf(context).scale(12) *
                                      1.5,
                              child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    for (final role in _roles)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(right: 15),
                                          child: InkWell(
                                              onTap: () =>
                                                  widget.onRole(role.id),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: SizedBox(
                                                  width: 55,
                                                  child: Column(children: [
                                                    AssistantAvatar(
                                                        role: role.name,
                                                        size: 52),
                                                    const SizedBox(height: 6),
                                                    Text(role.displayName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w500)),
                                                  ])))),
                                    InkWell(
                                        onTap: widget.onCreate,
                                        borderRadius: BorderRadius.circular(10),
                                        child: SizedBox(
                                            width: 55,
                                            child: Column(children: [
                                              Container(
                                                  width: 55,
                                                  height: 52,
                                                  decoration: BoxDecoration(
                                                      color: BingoPalette.blush,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14)),
                                                  child: const Icon(
                                                      Icons.add_rounded,
                                                      color: refMint,
                                                      size: 25)),
                                              const SizedBox(height: 6),
                                              const Text('创建搭子',
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: refMuted)),
                                            ]))),
                                  ])),
                        ])),
                    const SizedBox(height: 14),
                    BingoSurface(
                        radius: 15,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Column(children: [
                          _heading('我的分享', _shares.length, widget.onShares),
                          if (_shares.isEmpty)
                            Row(children: [
                              const Expanded(
                                  child: Text('把这份陪伴分享给大家',
                                      style: TextStyle(
                                          fontSize: 12, color: refMuted))),
                              TextButton(
                                  onPressed: widget.onShares,
                                  child: const Text('去分享',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600))),
                            ])
                          else
                            for (final share in _shares.take(2))
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  onTap: () => widget.onShare(share.id),
                                  leading: AssistantAvatar(
                                      role: _roles
                                          .where((r) =>
                                              r.displayName == share.name)
                                          .firstOrNull
                                          ?.name,
                                      size: 44),
                                  title: Text(share.name,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(share.introduction,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12, color: refMuted)),
                                  trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 20,
                                      color: refMuted)),
                        ])),
                    const SizedBox(height: 14),
                    BingoSurface(
                        radius: 15,
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          _menuRow(Icons.star_border_rounded, '我的收藏',
                              widget.onFavorites,
                              count: _favorites),
                          const Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: BingoPalette.line),
                          _menuRow(Icons.history_rounded, '聊天记录',
                              widget.onMessages ?? () => _showGroups(context)),
                          const Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: BingoPalette.line),
                          _menuRow(
                              Icons.settings_outlined, '设置', widget.onSettings),
                        ])),
                    const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: Row(children: [
                          Icon(Icons.shield_outlined,
                              size: 15, color: BingoPalette.muted),
                          SizedBox(width: 7),
                          Expanded(
                              child: Text('陪伴属于你，隐私也由你掌握。',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: BingoPalette.muted))),
                        ])),
                  ]))));
  void _showGroups(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
            const ListTile(
                title: Text('我的群聊',
                    style: TextStyle(fontWeight: FontWeight.w800))),
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
