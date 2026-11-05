import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/core/appearance/appearance_page.dart';
import 'dart:async';

import 'package:bingo/core/device/region_location_service.dart';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/user_setup_page.dart';
import 'package:bingo/features/settings/presentation/reference_my_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_page.dart';
import 'package:bingo/features/chat/presentation/location_picker_page.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:bingo/features/chat/presentation/incoming_call_page.dart';
import 'package:bingo/features/chat/presentation/realtime_call_page.dart';
import 'package:bingo/features/settings/presentation/settings_page.dart';
import 'package:bingo/features/roles/presentation/companion_space_page.dart';
import 'package:bingo/features/auth/presentation/role_editor_page.dart';
import 'package:bingo/features/roles/presentation/role_detail_page.dart';
import 'package:bingo/features/community/presentation/community_page.dart';
import 'package:bingo/features/community/presentation/publish_companion_page.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_detail_page.dart';
import 'package:bingo/features/conversations/presentation/messages_page.dart';
import 'package:bingo/features/group_chat/presentation/group_info_page.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/group_chat/presentation/group_chat_page.dart';
import 'package:bingo/features/group_chat/presentation/create_group_page.dart';
import 'package:bingo/features/group_chat/presentation/create_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _KeptTab extends StatefulWidget {
  const _KeptTab({required this.active, required this.child, super.key});
  final bool active;
  final Widget child;
  @override
  State<_KeptTab> createState() => _KeptTabState();
}

class _KeptTabState extends State<_KeptTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0, height: 1.5),
        child: ExcludeFocus(
            excluding: !widget.active,
            child: TickerMode(enabled: widget.active, child: widget.child)));
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.chatController,
    required this.gateway,
    required this.profile,
    required this.callCaptionsEnabled,
    required this.onCallCaptionsChanged,
    required this.onProfileSaved,
    required this.onLogout,
    this.onAccountDeleted,
    super.key,
  });

  final ChatController chatController;
  final HttpApiGateway gateway;
  final UserProfile profile;
  final bool callCaptionsEnabled;
  final Future<void> Function(bool enabled) onCallCaptionsChanged;
  final ValueChanged<UserProfile> onProfileSaved;
  final VoidCallback onLogout;
  final Future<void> Function()? onAccountDeleted;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final AppearanceStore _appearance;
  final _location = const RegionLocationService();
  bool _locating = false;
  int _locationGeneration = 0;
  ChatController get chatController => widget.chatController;
  HttpApiGateway get gateway => widget.gateway;
  UserProfile get profile => widget.profile;
  bool get callCaptionsEnabled => widget.callCaptionsEnabled;
  Future<void> Function(bool) get onCallCaptionsChanged =>
      widget.onCallCaptionsChanged;
  ValueChanged<UserProfile> get onProfileSaved => widget.onProfileSaved;
  VoidCallback get onLogout => widget.onLogout;
  static const _deviceChannel = MethodChannel('bingo/device_tools');
  final _rolesKey = GlobalKey<CompanionSpacePageState>();
  final _communityKey = GlobalKey<CommunityPageState>();
  final _conversationsKey = GlobalKey<MessagesPageState>();
  final _myKey = GlobalKey<ReferenceMyPageState>();
  int _tab = 0;
  final _pages = PageController();
  int _unreadChats = 0;
  bool _showingIncoming = false;
  bool _loadingRoleDetails = false;
  Timer? _welcomeTimer;
  bool _welcomePolling = false, _welcomeErrorShown = false;
  bool _welcomeRescanRequested = false;
  bool _welcomeForeground = true;

  @override
  void initState() {
    super.initState();
    _appearance = AppearanceStore(profile.id);
    unawaited(_appearance.load().catchError((Object _) {}));
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshLocation());
    chatController.addListener(_onChatChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChatChanged());
    unawaited(_pollWelcomes());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _welcomeForeground = true;
    if (state == AppLifecycleState.resumed) unawaited(_refreshLocation());
    if (state == AppLifecycleState.resumed) unawaited(_pollWelcomes());
    if (state == AppLifecycleState.paused) {
      _welcomeForeground = false;
      _welcomeTimer?.cancel();
      _welcomeTimer = null;
      unawaited(_location.cancel().catchError((Object _) {}));
    }
  }

  Future<void> _refreshLocation({bool retry = false}) async {
    if (_locating) return;
    _locating = true;
    final generation = ++_locationGeneration;
    final userId = profile.id;
    bool active() =>
        mounted && generation == _locationGeneration && profile.id == userId;
    try {
      final enabled = await _location.isEnabled(userId);
      if (!active()) return;
      if (!enabled) {
        await gateway.clearCurrentRegion();
        return;
      }
      final region = await _location.current(retry: retry);
      if (!active()) return;
      if (region == null) {
        await gateway.clearCurrentRegion();
      } else {
        await gateway.saveCurrentRegion(region);
      }
    } on Exception {
      return;
    } finally {
      if (generation == _locationGeneration) _locating = false;
    }
  }

  void _onChatChanged() {
    final invitation = chatController.takeIncomingCall();
    if (invitation == null || _showingIncoming || !mounted) return;
    _showingIncoming = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (mounted) await _openIncomingCall(context, invitation);
      } finally {
        _showingIncoming = false;
      }
    });
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    _pages.dispose();
    _updateCommunityChrome(false);
    _appearance.dispose();
    _locationGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_location.cancel().catchError((Object _) {}));
    chatController.removeListener(_onChatChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: BingoPalette.ice,
        body: PageView(
            key: const ValueKey('main-pages'),
            controller: _pages,
            allowImplicitScrolling: true,
            onPageChanged: (tab) {
              if (_tab != tab) _activateTab(tab);
            },
            children: <Widget>[
              CompanionSpacePage(
                key: _rolesKey,
                userId: profile.id,
                gateway: gateway,
                groups: gateway,
                community: gateway,
                onRecommendation: _openCommunityShare,
                onInstalled: _refreshPartners,
                onChat: _openRole,
                onDetail: (role) => _openCopy(role.id),
                onOpenGroup: _openGroup,
                onCreateGroup: _createGroup,
                onCreateRole: _newRole,
                onCommunity: () => _selectTab(2),
                onMessages: () {
                  _onTabReady(
                      1, () => _conversationsKey.currentState?.showChats());
                },
                onSearchChats: () {
                  _onTabReady(
                      1,
                      () => _conversationsKey.currentState
                          ?.showChats(search: true));
                },
                onAllGroups: () {
                  _onTabReady(
                      1, () => _conversationsKey.currentState?.onlyGroups());
                },
              ),
              MessagesPage(
                  key: _conversationsKey,
                  showCreateAction: false,
                  gateway: gateway,
                  groups: gateway,
                  onRole: _openRole,
                  onGroup: _openGroup,
                  onUnreadChanged: (count) {
                    if (mounted && _unreadChats != count) {
                      setState(() => _unreadChats = count);
                    }
                  },
                  onCreate: () => _createGroup('快乐小窝'),
                  onCreateRole: _newRole,
                  onCommunity: () => _selectTab(2),
                  onGroupInfo: (group) async {
                    await Navigator.of(context).push<bool>(MaterialPageRoute(
                        builder: (_) => GroupInfoPage(
                            group: group,
                            gateway: gateway,
                            roles: gateway,
                            userAvatarData: profile.userAvatarData,
                            appearanceStore: _appearance)));
                    if (mounted) await _refreshPartners();
                  },
                  onPartners: () => _selectTab(0)),
              CommunityPage(
                  key: _communityKey,
                  gateway: gateway,
                  referenceDesign: true,
                  onCreateGroup: _createGroup,
                  onPublish: _publish,
                  onInstalled: (_) => _refreshPartners(),
                  onOpenCopy: _openCopy,
                  onChatCopy: _chatCopy),
              ReferenceMyPage(
                  key: _myKey,
                  profile: profile,
                  roles: gateway,
                  groups: gateway,
                  community: gateway,
                  onEdit: () async {
                    await _openProfileSetup(context, profile);
                  },
                  onSettings: () => _openSettings(context),
                  onAppearance: () async {
                    await Navigator.of(context).push<void>(MaterialPageRoute(
                        builder: (_) => AppearancePage(store: _appearance)));
                  },
                  onMessages: () {
                    _onTabReady(
                        1, () => _conversationsKey.currentState?.showChats());
                  },
                  onGroups: () {
                    _onTabReady(
                        1, () => _conversationsKey.currentState?.onlyGroups());
                  },
                  onRole: _openCopy,
                  onGroup: _openGroup,
                  onShare: _openCommunityShare,
                  onCreate: _newRole,
                  onPartners: () => _selectTab(0),
                  onShares: () {
                    _onTabReady(
                        2, () => _communityKey.currentState?.showScope(3));
                  },
                  onFavorites: () {
                    _onTabReady(
                        2, () => _communityKey.currentState?.showScope(2));
                  }),
            ]
                .indexed
                .map((entry) => _KeptTab(
                    key: ValueKey(entry.$1),
                    active: _tab == entry.$1,
                    child: entry.$2))
                .toList()),
        bottomNavigationBar: _navigation(),
      );

  void _selectTab(int tab) {
    _activateTab(tab);
    if (_pages.hasClients) _pages.jumpToPage(tab);
  }

  Future<void> _pollWelcomes() async {
    if (!mounted || !_welcomeForeground) return;
    if (_welcomePolling) {
      _welcomeRescanRequested = true;
      return;
    }
    _welcomePolling = true;
    try {
      final status = await gateway.welcomeStatus();
      if (!mounted || !_welcomeForeground) return;
      await _rolesKey.currentState?.refresh(recommendations: false);
      await _conversationsKey.currentState?.refresh();
      if (!mounted || !_welcomeForeground) return;
      _welcomeTimer?.cancel();
      _welcomeTimer = null;
      if (status['pending'] == true) {
        _welcomeTimer = Timer(const Duration(milliseconds: 1500),
            () => unawaited(_pollWelcomes()));
      }
      if ((status['failed'] as int? ?? 0) > 0 && !_welcomeErrorShown) {
        _welcomeErrorShown = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('部分搭子的招呼暂未生成成功'),
            action: SnackBarAction(
                label: '重试',
                onPressed: () async {
                  try {
                    await gateway.retryWelcomes();
                    chatController.resumeWelcome();
                    _welcomeErrorShown = false;
                    unawaited(_pollWelcomes());
                  } catch (_) {}
                })));
      }
    } catch (_) {
      // A transient status failure must not interrupt ordinary chat.
      if (mounted && _welcomeForeground) {
        _welcomeTimer?.cancel();
        _welcomeTimer =
            Timer(const Duration(seconds: 5), () => unawaited(_pollWelcomes()));
      }
    } finally {
      _welcomePolling = false;
      if (_welcomeRescanRequested && mounted && _welcomeForeground) {
        _welcomeRescanRequested = false;
        _welcomeTimer?.cancel();
        _welcomeTimer = Timer(Duration.zero, () => unawaited(_pollWelcomes()));
      }
    }
  }

  void _onTabReady(int tab, VoidCallback action) {
    _selectTab(tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tab == tab) action();
    });
  }

  void _activateTab(int tab) {
    if (_tab != tab) FocusScope.of(context).unfocus();
    setState(() => _tab = tab);
    _updateCommunityChrome(tab != 0);
    if (tab == 0) unawaited(_rolesKey.currentState?.refresh());
    if (tab == 1) unawaited(_conversationsKey.currentState?.refresh());
    if (tab == 2) unawaited(_communityKey.currentState?.refresh());
    if (tab == 3) unawaited(_myKey.currentState?.refresh());
  }

  Widget _navigation() => ReferenceNavigation(
      selected: _tab,
      onSelected: _selectTab,
      onCreate: _create,
      unread: _unreadChats);

  void _updateCommunityChrome(bool enabled) {
    unawaited(const MethodChannel('bingo/device_tools').invokeMethod<void>(
        'setCommunityChrome', {'enabled': enabled}).catchError((Object _) {}));
  }

  Future<void> _refreshPartners() async {
    await _rolesKey.currentState?.refresh();
    await _conversationsKey.currentState?.refresh();
    if (mounted) unawaited(_pollWelcomes());
  }

  Future<void> _publish([RoleOption? role]) async {
    final share = await Navigator.of(context).push<CommunityShare>(
        MaterialPageRoute(
            builder: (_) => PublishCompanionPage(
                gateway: gateway, roleGateway: gateway, initialRole: role)));
    if (share != null && mounted) {
      _onTabReady(2, () => _communityKey.currentState?.showScope(3));
      showCenterToast(context, '搭子已分享到社区');
    }
  }

  Future<void> _openCopy(String id, {bool returnToChat = false}) async {
    if (_loadingRoleDetails) return;
    _loadingRoleDetails = true;
    late final List<RoleOption> roles;
    try {
      roles = await gateway.listRoles();
    } on Exception {
      if (mounted) showCenterToast(context, '搭子详情暂时无法打开，请稍后重试');
      return;
    } finally {
      _loadingRoleDetails = false;
    }
    final role = roles.where((role) => role.id == id).firstOrNull;
    if (!mounted) return;
    if (role == null) {
      showCenterToast(context, '搭子暂时不可用');
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => RoleDetailPage(
            role: role,
            gateway: gateway,
            userAvatarData: profile.userAvatarData,
            userName: profile.username ?? '',
            onChat: returnToChat
                ? (_) async => Navigator.of(context).pop()
                : _openRole,
            onShare: (role) => _publish(role),
            onEdit: () async {
              final current = await gateway.listRoles();
              if (!mounted) return;
              final latest = current.where((item) => item.id == id).firstOrNull;
              if (latest == null) return;
              await Navigator.of(context).push<RoleOption>(MaterialPageRoute(
                  builder: (_) => RoleEditorPage(
                      gateway: gateway, roles: current, role: latest)));
              await _refreshPartners();
            })));
    await _refreshPartners();
  }

  Future<void> _openCommunityShare(String id) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => CommunityDetailPage(
            gateway: gateway,
            shareId: id,
            onInstalled: (_) => _refreshPartners(),
            onOpenCopy: _openCopy,
            referenceDesign: true,
            onChatCopy: _chatCopy)));
  }

  Future<void> _chatCopy(String id) async {
    final roles = await gateway.listRoles();
    final role = roles.where((role) => role.id == id).firstOrNull;
    if (!mounted) return;
    if (role == null) {
      showCenterToast(context, '搭子暂时不存在');
      return;
    }
    await _openRole(role);
  }

  Future<void> _newRole() async {
    final roles = await gateway.listRoles();
    if (!mounted) return;
    await Navigator.of(context).push<RoleOption>(MaterialPageRoute(
        builder: (_) => RoleEditorPage(gateway: gateway, roles: roles)));
    if (mounted) await _refreshPartners();
  }

  Future<void> _createGroup(String name) async {
    final group = await Navigator.of(context).push<ChatGroup>(MaterialPageRoute(
        builder: (_) => CreateGroupPage(
            gateway: gateway, roles: gateway, initialName: name)));
    if (group != null && mounted) await _openGroup(group);
    if (mounted) await _refreshPartners();
  }

  Future<void> _openGroup(ChatGroup group) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => GroupChatPage(
            groupId: group.id,
            gateway: gateway,
            roles: gateway,
            speech: gateway,
            onOpenRoleDetails: _openCopy,
            userAvatarData: profile.userAvatarData,
            appearanceStore: _appearance)));
    if (mounted) await _refreshPartners();
  }

  Future<void> _create() async {
    _updateCommunityChrome(false);
    FocusScope.of(context).unfocus();
    final previousTab = _tab;
    int? destination;
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => CreateCenterPage(
            onDestination: (tab) {
              destination = tab;
              Navigator.of(context).pop();
              _selectTab(tab);
            },
            onCreateRole: _newRole,
            onCreateGroup: () => _createGroup('快乐小窝'),
            onPublish: _publish)));
    if (mounted) _updateCommunityChrome(_tab != 0);
    if (mounted && destination == null && _tab != previousTab) {
      _selectTab(previousTab);
    }
  }

  Future<void> _openRole(RoleOption role) async {
    try {
      await _appearance.load();
    } catch (_) {
      if (mounted) showCenterToast(context, '外观配置读取失败，请重新打开应用重试');
    }
    final conversation = await gateway.openRoleConversation(role.id);
    final selected = await gateway.getProfile();
    if (!mounted) return;
    onProfileSaved(selected);
    await chatController.bindConversation(
        profile.id, conversation.id, role.name,
        welcomeUnread: conversation.welcomeUnread);
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (chatContext) => _chatPage(chatContext, role),
    ));
    await gateway.markConversationRead(conversation.id);
    final updated = await gateway.getProfile();
    if (mounted) onProfileSaved(updated);
    await _refreshPartners();
  }

  Widget _chatPage(BuildContext context, RoleOption role) {
    return ChatPage(
      infoGateway: gateway,
      onOpenRoleDetails: () => _openCopy(role.id, returnToChat: true),
      appearanceStore: _appearance,
      appearanceRoleId: role.id,
      controller: chatController,
      assistantName: role.displayName,
      assistantRole: role.name,
      speechGateway: gateway,
      onStartCall: () => _openRealtimeCall(context,
          assistantName: role.displayName, assistantRole: role.name),
      onIncomingCall: (invitation) => _openIncomingCall(context, invitation),
      onPickGallery: () => _pickImage(context, 'pickImage'),
      onTakePhoto: () => _pickImage(context, 'takePhoto'),
      onLocation: () => _pickLocation(context),
      userAvatarData: profile.userAvatarData,
      locationMapUrlBuilder: (location) => gateway.locationMapUrl(location),
      imageUrlBuilder: (imageId) => gateway.imageUrl(imageId),
      imageAccessToken: gateway.accessToken,
      onOpenSettings: () => _openSettings(context),
      onBack: () => Navigator.of(context).pop(),
    );
  }

  Future<void> _pickLocation(BuildContext context) async {
    final location = await Navigator.of(context).push<ChatLocation>(
        MaterialPageRoute(
            builder: (_) => LocationPickerPage(
                gateway: gateway,
                accessToken: gateway.accessToken,
                userId: profile.id)));
    if (location != null && context.mounted) {
      await chatController.sendLocation(location);
    }
  }

  Future<void> _pickImage(BuildContext context, String method) async {
    try {
      final result =
          await _deviceChannel.invokeMapMethod<Object?, Object?>(method);
      if (result == null || !context.mounted) return;
      final bytes = result['bytes'] as Uint8List?;
      final mimeType = result['mime_type'] as String? ?? 'image/jpeg';
      if (bytes == null || bytes.isEmpty) return;
      await chatController.sendImage(
        bytes,
        mimeType: mimeType,
      );
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      showCenterToast(context, error.message ?? '无法读取图片');
    }
  }

  Future<void> _openRealtimeCall(
    BuildContext context, {
    String? conversationId,
    String? callId,
    String? assistantName,
    String? assistantRole,
  }) async {
    final completedConversationId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RealtimeCallPage(
          gateway: gateway,
          conversationId: conversationId ?? chatController.conversationId,
          callId: callId,
          assistantName: assistantName ?? profile.role ?? 'Bingo',
          assistantRole: assistantRole ?? profile.role,
          showCaptions: callCaptionsEnabled,
        ),
      ),
    );
    if (completedConversationId != null &&
        completedConversationId == chatController.conversationId) {
      await chatController.reloadConversation(completedConversationId);
    }
    await _rolesKey.currentState?.refresh();
  }

  Future<void> _openIncomingCall(
    BuildContext context,
    IncomingCallInvitation invitation,
  ) async {
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallPage(
          gateway: gateway,
          invitation: invitation,
        ),
      ),
    );
    if (!context.mounted) return;
    if (accepted ?? false) {
      await _openRealtimeCall(
        context,
        conversationId: invitation.conversationId,
        callId: invitation.id,
        assistantName: invitation.callerName,
        assistantRole: invitation.callerRole,
      );
    } else if (chatController.conversationId == invitation.conversationId) {
      await chatController.reloadConversation(invitation.conversationId);
    }
    await _rolesKey.currentState?.refresh();
  }

  Future<void> _openSettings(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (settingsContext) => SettingsPage(
          gateway: gateway,
          profile: profile,
          onOpenAppearance: () async {
            try {
              await _appearance.load();
              if (settingsContext.mounted) {
                await Navigator.of(settingsContext).push<void>(
                    MaterialPageRoute(
                        builder: (_) => AppearancePage(store: _appearance)));
              }
            } catch (_) {
              if (settingsContext.mounted) {
                showCenterToast(settingsContext, '无法读取聊天外观，请重试');
              }
            }
          },
          callCaptionsEnabled: callCaptionsEnabled,
          onCallCaptionsChanged: onCallCaptionsChanged,
          onEditProfile: (currentProfile) =>
              _openProfileSetup(settingsContext, currentProfile),
          onLogout: () {
            Navigator.of(settingsContext).popUntil((route) => route.isFirst);
            onLogout();
          },
          onAccountDeleted: widget.onAccountDeleted == null
              ? null
              : () async {
                  Navigator.of(settingsContext)
                      .popUntil((route) => route.isFirst);
                  await widget.onAccountDeleted!();
                },
        ),
      ),
    );
    await chatController.refreshEngagement();
  }

  Future<UserProfile?> _openProfileSetup(
    BuildContext context,
    UserProfile currentProfile,
  ) {
    return Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(
        builder: (profileContext) => UserSetupPage(
          gateway: gateway,
          profile: currentProfile,
          isEditing: true,
          onSaved: (updated) {
            onProfileSaved(updated);
            Navigator.of(profileContext).pop(updated);
          },
        ),
      ),
    );
  }
}
