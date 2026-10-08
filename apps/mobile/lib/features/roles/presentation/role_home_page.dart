import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/push/push_role_avatar_cache.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/role_editor_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/roles/role_traits.dart';
import 'package:bingo/features/roles/data/local_role_order_store.dart';
import 'package:bingo/features/roles/presentation/role_detail_page.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/partner_action_icon.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:bingo/shared/widgets/partner_swipe_card.dart';
import 'package:bingo/core/role_avatar_store.dart';
import 'package:flutter/material.dart';

class RoleHomePage extends StatefulWidget {
  const RoleHomePage(
      {required this.gateway,
      required this.userId,
      required this.onOpenRole,
      this.orderStore = const AndroidLocalRoleOrderStore(),
      this.onRolesChanged,
      this.onOpenSettings,
      this.userAvatarData,
      super.key});
  final RoleGateway gateway;
  final String userId;
  final LocalRoleOrderStore orderStore;
  final Future<void> Function(RoleOption role) onOpenRole;
  final Future<void> Function()? onRolesChanged;
  final VoidCallback? onOpenSettings;
  final String? userAvatarData;
  @override
  State<RoleHomePage> createState() => RoleHomePageState();
}

class RoleHomePageState extends State<RoleHomePage>
    with WidgetsBindingObserver {
  List<RoleOption>? _roles;
  String? _error;
  String? _openingId;
  bool _loading = false;
  bool _dragging = false;
  bool _orderLoaded = false;
  List<String> _orderIds = [];
  int _accountVersion = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    _timer = Timer.periodic(
        const Duration(seconds: 30), (_) => unawaited(refresh()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_loading || _dragging) return;
    _loading = true;
    final userId = widget.userId;
    final accountVersion = _accountVersion;
    try {
      if (!_orderLoaded) {
        var orderIds = <String>[];
        try {
          orderIds = await widget.orderStore.load(userId);
        } on Exception {
          if (mounted && accountVersion == _accountVersion) {
            showCenterToast(context, '本地排序读取失败，暂时使用默认顺序');
          }
        }
        if (!mounted || accountVersion != _accountVersion) return;
        _orderIds = orderIds;
        _orderLoaded = true;
      }
      final roles = await widget.gateway.listRoles();
      if (mounted && accountVersion == _accountVersion && !_dragging) {
        unawaited(PushRoleAvatarCache.sync(userId, roles));
        setState(() {
          _roles = applyLocalRoleOrder(roles, _orderIds);
          _error = null;
        });
      }
    } on Exception {
      if (mounted && accountVersion == _accountVersion) {
        setState(() => _error = '伙伴加载失败，请重试');
      }
    } finally {
      if (accountVersion == _accountVersion) _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant RoleHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _accountVersion++;
      _roles = null;
      _orderIds = [];
      _orderLoaded = false;
      _error = null;
      _dragging = false;
      _loading = false;
      unawaited(refresh());
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final roles = _roles;
    if (roles == null || _openingId != null) return;
    if (newIndex == oldIndex) return;
    final userId = widget.userId;
    setState(() {
      final role = roles.removeAt(oldIndex);
      roles.insert(newIndex, role);
      _orderIds = roles.map((role) => role.id).toList();
    });
    try {
      await widget.orderStore.save(userId, List.of(_orderIds));
    } on Exception {
      if (mounted && userId == widget.userId) {
        showCenterToast(context, '排序保存失败，请重新拖动尝试');
      }
    }
  }

  Future<void> _open(RoleOption role) async {
    if (_openingId != null) return;
    setState(() => _openingId = role.id);
    try {
      await widget.onOpenRole(role);
    } on ApiException catch (error) {
      if (mounted) showCenterToast(context, error.message);
    } on Exception {
      if (mounted) showCenterToast(context, '暂时无法进入聊天，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _openingId = null);
        await refresh();
      }
    }
  }

  Future<void> _edit([RoleOption? role]) async {
    if (_openingId != null) return;
    await Navigator.of(context).push<RoleOption>(MaterialPageRoute(
        builder: (_) => RoleEditorPage(
            gateway: widget.gateway, roles: _roles ?? [], role: role)));
    if (!mounted) return;
    await refresh();
    await widget.onRolesChanged?.call();
  }

  Future<void> _detail(RoleOption role) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => RoleDetailPage(
            role: role,
            userAvatarData: widget.userAvatarData,
            gateway: widget.gateway,
            onChat: _open,
            onEdit: () => _edit(role))));
    await refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = _roles;
    return DecoratedBox(
        decoration:
            const BoxDecoration(gradient: BingoPalette.companionGradient),
        child: DecoratedBox(
            key: const ValueKey('companion-background'),
            decoration:
                const BoxDecoration(gradient: BingoPalette.companionGlow),
            child: SafeArea(
                child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(18, 19, 18, 20),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('陪伴空间',
                              style: TextStyle(
                                  fontSize: 23, fontWeight: FontWeight.w800)),
                          SizedBox(height: 5),
                          Text('在这里，慢慢聊~',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF85928F))),
                        ])),
                    IconButton(
                        tooltip: '我的',
                        onPressed: widget.onOpenSettings,
                        icon: UserAvatar(
                            avatarData: widget.userAvatarData, size: 42)),
                  ])),
              Expanded(
                  child: RefreshIndicator(
                      onRefresh: refresh,
                      child: roles != null && roles.isNotEmpty
                          ? ReorderableListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              buildDefaultDragHandles: false,
                              itemCount: roles.length,
                              onReorderStart: (_) => _dragging = true,
                              onReorderEnd: (_) => _dragging = false,
                              onReorderItem: _reorder,
                              proxyDecorator: (child, index, animation) =>
                                  Material(
                                      color: Colors.transparent,
                                      elevation: 6,
                                      borderRadius: BorderRadius.circular(25),
                                      child: child),
                              header: _error == null
                                  ? null
                                  : TextButton(
                                      onPressed: refresh, child: Text(_error!)),
                              itemBuilder: (context, index) =>
                                  ReorderableDelayedDragStartListener(
                                      key: ValueKey(roles[index].id),
                                      enabled: _openingId == null,
                                      index: index,
                                      child: _card(roles[index])))
                          : ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              children: [
                                  if (_error != null)
                                    Column(children: [
                                      Text(_error!),
                                      TextButton(
                                          onPressed: refresh,
                                          child: const Text('重新加载'))
                                    ]),
                                  if (_roles == null && _error == null)
                                    const Padding(
                                        padding: EdgeInsets.all(50),
                                        child: Center(
                                            child:
                                                CircularProgressIndicator())),
                                  if (roles != null && roles.isEmpty)
                                    const Padding(
                                        padding: EdgeInsets.all(40),
                                        child: Center(
                                            child: Text('还没有伙伴，创建一位新的伙伴吧'))),
                                  ...?roles?.map(_card),
                                ]))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                          onPressed: _openingId == null ? _edit : null,
                          icon: const PartnerActionIcon(
                              symbol: PartnerActionSymbol.create,
                              size: 25,
                              color: BingoPalette.companionActionIcon),
                          label: const Text('创建伙伴',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          style: companionActionButtonStyle(height: 56)))),
            ]))));
  }

  Widget _card(RoleOption role) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PartnerSwipeCard(
          enabled: _openingId == null && !_dragging,
          onEdit: () => _edit(role),
          onDelete: role.builtin ? null : () => _deleteRole(role),
          child: Material(
              color: Colors.white.withValues(alpha: .93),
              borderRadius: BorderRadius.circular(25),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                  onTap: _openingId == null ? () => _detail(role) : null,
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(children: [
                        Row(children: [
                          AssistantAvatar(role: role.name, size: 64),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(role.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800))),
                                  _enterButton(role),
                                ]),
                                const SizedBox(height: 6),
                                Text(role.cardDescription,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF85928F))),
                              ])),
                        ]),
                        const SizedBox(height: 12),
                        SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final label in role.traits)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: TraitBadge(label)),
                                    ]))),
                      ]))))));

  Future<void> _deleteRole(RoleOption role) async {
    if (_openingId != null || role.builtin) return;
    final affected = (_roles ?? [])
        .where((item) => item.id != role.id && item.voiceSourceId == role.id)
        .length;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('删除${role.displayName}？'),
                content: Text('删除后，该伙伴的专属音色也会失效。'
                    '${affected > 0 ? '\n另外 $affected 位伙伴使用了这个音色，将自动切回系统默认音色。' : ''}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除',
                          style: TextStyle(color: Color(0xFFC3676D)))),
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _openingId = role.id);
    try {
      await widget.gateway.deleteRole(role.id);
      RoleAvatarStore.set(role.name, null);
      await refresh();
      await widget.onRolesChanged?.call();
    } on Exception catch (error) {
      if (mounted) {
        showCenterToast(
            context, error is ApiException ? error.message : '删除失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Widget _enterButton(RoleOption role) =>
      Stack(clipBehavior: Clip.none, children: [
        SizedBox(
            height: 32,
            child: TextButton.icon(
                onPressed: _openingId == null ? () => _open(role) : null,
                style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFE9F8F2),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: const StadiumBorder()),
                icon: _openingId == role.id
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const TraitIcon('chat', size: 16),
                label: const Text('进入', style: TextStyle(fontSize: 12)))),
        if (role.unreadCount > 0)
          Positioned(
              top: -6,
              right: -4,
              child: IgnorePointer(
                  child: Semantics(
                      label: '${role.unreadCount}条未读消息',
                      child: Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFF4057),
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(
                              role.unreadCount > 99
                                  ? '99+'
                                  : '${role.unreadCount}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)))))),
      ]);
}
