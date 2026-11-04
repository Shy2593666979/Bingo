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
  final Future<void> Function(String) onRole, onShare;
  final Future<void> Function(ChatGroup) onGroup;
  @override
  State<ReferenceMyPage> createState() => ReferenceMyPageState();
}

class ReferenceMyPageState extends State<ReferenceMyPage> {
  List<RoleOption> _roles = [];
  List<ChatGroup> _groups = [];
  int _shareCount = 0;
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
      if (mounted) {
        setState(() {
          _roles = roles;
          _groups = groups;
          _shareCount = shares.total ?? shares.items.length;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Widget _stat(String label, int count, VoidCallback onTap) => Expanded(
      child: InkWell(
          onTap: onTap,
          child: Column(children: [
            Text('$count',
                style: CompanionLaunch.text(23, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style:
                    CompanionLaunch.text(16, color: const Color(0xFF647E6B))),
          ])));

  Widget _menu(IconData icon, String title, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Container(
          constraints: const BoxConstraints(minHeight: 63),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: CompanionLaunch.line))),
          child: Row(children: [
            Icon(icon, size: 25, color: const Color(0xFF284A33)),
            const SizedBox(width: 21),
            Expanded(
                child: Text(title,
                    style: CompanionLaunch.text(
                        CompanionLaunch.compact(context) ? 18 : 19))),
            const Icon(Icons.chevron_right_rounded,
                size: 19, color: Color(0xFF91A895)),
          ])));

  @override
  Widget build(BuildContext context) {
    final compact = CompanionLaunch.compact(context);
    return DecoratedBox(
        decoration: CompanionLaunch.background,
        child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                    padding: EdgeInsets.zero,
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const CompanionLaunchHeader('我的'),
                      Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: compact ? 23 : 27),
                          child: Column(children: [
                            const SizedBox(height: 30),
                            InkWell(
                                onTap: widget.onEdit,
                                borderRadius: BorderRadius.circular(23),
                                child: Padding(
                                    padding: EdgeInsets.only(
                                        left: compact ? 12 : 16),
                                    child: Row(children: [
                                      Stack(clipBehavior: Clip.none, children: [
                                        UserAvatar(
                                            avatarData:
                                                widget.profile.userAvatarData,
                                            username:
                                                widget.profile.username ?? '',
                                            size: compact ? 80 : 88,
                                            foregroundColor: Colors.white,
                                            backgroundGradient:
                                                const LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                  Color(0xFF32C89B),
                                                  CompanionLaunch.primary
                                                ])),
                                        if (widget.profile.userAvatarData ==
                                            null)
                                          const Positioned(
                                              right: -15,
                                              top: -9,
                                              child: SizedBox(
                                                  width: 29,
                                                  height: 29,
                                                  child: CustomPaint(
                                                      painter:
                                                          _ProfileRays()))),
                                      ]),
                                      SizedBox(width: compact ? 23 : 27),
                                      Expanded(
                                          child: Text(
                                              widget.profile.username ??
                                                  'Bingo 用户',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: CompanionLaunch.text(
                                                  compact ? 25 : 27,
                                                  weight: FontWeight.w700))),
                                      const Icon(Icons.chevron_right_rounded,
                                          size: 19, color: Color(0xFF6E8C77)),
                                    ]))),
                            const SizedBox(height: 20),
                            Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 9),
                                child: Row(children: [
                                  _stat('搭子', _roles.length, widget.onPartners),
                                  _stat('分享', _shareCount, widget.onShares),
                                  _stat(
                                      '群聊',
                                      _groups.length,
                                      widget.onGroups ??
                                          () => _showGroups(context)),
                                ])),
                            if (_failed)
                              TextButton(
                                  onPressed: refresh,
                                  child: const Text('部分信息加载失败，点击重试')),
                            const SizedBox(height: 18),
                            const Divider(
                                height: 1, color: CompanionLaunch.line),
                            _menu(Icons.edit_outlined, '我的分享', widget.onShares),
                            _menu(Icons.star_border_rounded, '我的收藏',
                                widget.onFavorites),
                            _menu(Icons.chat_bubble_outline_rounded, '聊天外观',
                                widget.onAppearance ?? widget.onSettings),
                            _menu(Icons.settings_outlined, '设置',
                                widget.onSettings),
                            const SizedBox(height: 24),
                          ])),
                    ]))));
  }

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

class _ProfileRays extends CustomPainter {
  const _ProfileRays();
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = const Color(0xFF8EDAB6)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(7, 3), const Offset(3, 12), pen);
    canvas.drawLine(const Offset(21, 14), const Offset(13, 18), pen);
  }

  @override
  bool shouldRepaint(_ProfileRays oldDelegate) => false;
}
