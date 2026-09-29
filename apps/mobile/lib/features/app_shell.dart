import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/profile_setup_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/chat_page.dart';
import 'package:bingo/features/chat/presentation/incoming_call_page.dart';
import 'package:bingo/features/chat/presentation/realtime_call_page.dart';
import 'package:bingo/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.chatController,
    required this.gateway,
    required this.profile,
    required this.callCaptionsEnabled,
    required this.onCallCaptionsChanged,
    required this.onProfileSaved,
    required this.onLogout,
    super.key,
  });

  final ChatController chatController;
  final HttpApiGateway gateway;
  final UserProfile profile;
  final bool callCaptionsEnabled;
  final Future<void> Function(bool enabled) onCallCaptionsChanged;
  final ValueChanged<UserProfile> onProfileSaved;
  final VoidCallback onLogout;
  static const _deviceChannel = MethodChannel('bingo/device_tools');

  @override
  Widget build(BuildContext context) {
    return ChatPage(
      controller: chatController,
      assistantName: profile.assistantName ?? 'Bingo',
      assistantRole: profile.role,
      speechGateway: gateway,
      onStartCall: () => _openRealtimeCall(context),
      onIncomingCall: (invitation) => _openIncomingCall(context, invitation),
      onPickGallery: () => _pickImage(context, 'pickImage'),
      onTakePhoto: () => _pickImage(context, 'takePhoto'),
      imageUrlBuilder: (imageId) => gateway.imageUrl(imageId),
      imageAccessToken: gateway.accessToken,
      onOpenSettings: () => _openSettings(context),
    );
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
  }) async {
    final completedConversationId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RealtimeCallPage(
          gateway: gateway,
          conversationId: conversationId ?? chatController.conversationId,
          callId: callId,
          assistantName: profile.assistantName ?? 'Bingo',
          assistantRole: profile.role,
          showCaptions: callCaptionsEnabled,
        ),
      ),
    );
    if (completedConversationId != null) {
      await chatController.reloadConversation(completedConversationId);
    }
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
      );
    } else {
      await chatController.reloadConversation(invitation.conversationId);
    }
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
            Navigator.of(settingsContext).pop();
            onLogout();
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
        builder: (profileContext) => ProfileSetupPage(
          gateway: gateway,
          profile: currentProfile,
          onCancel: () => Navigator.of(profileContext).pop(),
          onSaved: (updated) {
            onProfileSaved(updated);
            Navigator.of(profileContext).pop(updated);
          },
        ),
      ),
    );
  }
}
