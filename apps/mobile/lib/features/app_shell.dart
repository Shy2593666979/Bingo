import 'dart:async';

import 'package:bingo/core/device/region_location_service.dart';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/user_setup_page.dart';
import 'package:bingo/features/settings/presentation/my_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_page.dart';
import 'package:bingo/features/chat/presentation/location_picker_page.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:bingo/features/chat/presentation/incoming_call_page.dart';
import 'package:bingo/features/chat/presentation/realtime_call_page.dart';
import 'package:bingo/features/settings/presentation/settings_page.dart';
import 'package:bingo/features/roles/presentation/role_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _rolesKey = GlobalKey<RoleHomePageState>();
  bool _showingIncoming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshLocation());
    chatController.addListener(_onChatChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChatChanged());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshLocation());
    if (state == AppLifecycleState.paused) {
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
    _locationGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_location.cancel().catchError((Object _) {}));
    chatController.removeListener(_onChatChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: BingoPalette.ice,
        body: RoleHomePage(
          key: _rolesKey,
          userId: profile.id,
          gateway: gateway,
          userAvatarData: profile.userAvatarData,
          onOpenRole: _openRole,
          onOpenSettings: () => _openMy(context),
          onRolesChanged: () async {
            final updated = await gateway.getProfile();
            if (mounted) onProfileSaved(updated);
          },
        ),
      );

  Future<void> _openRole(RoleOption role) async {
    final conversation = await gateway.openRoleConversation(role.id);
    final selected = await gateway.getProfile();
    if (!mounted) return;
    onProfileSaved(selected);
    await chatController.bindConversation(
        profile.id, conversation.id, role.name);
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (chatContext) => _chatPage(chatContext, role),
    ));
    await gateway.markConversationRead(conversation.id);
    final updated = await gateway.getProfile();
    if (mounted) onProfileSaved(updated);
  }

  Widget _chatPage(BuildContext context, RoleOption role) {
    return ChatPage(
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

  Future<void> _openMy(BuildContext context) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (myContext) => MyPage(
            profile: profile,
            onEditUser: (current) => _openProfileSetup(myContext, current),
            onOpenSettings: () => _openSettings(myContext))));
  }
}
