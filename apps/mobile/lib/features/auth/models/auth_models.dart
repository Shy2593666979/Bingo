import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/core/role_avatar_assets.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.phone,
    required this.username,
    required this.assistantName,
    required this.personality,
    required this.role,
    required this.onboardingComplete,
    this.companionSelectionComplete = true,
    this.roleId,
    this.birthday,
    this.gender,
    this.userAvatarData,
  });

  final String id;
  final String phone;
  final String? username;
  final String? assistantName;
  final String? personality;
  final String? role;
  final bool onboardingComplete;
  final bool companionSelectionComplete;
  final String? roleId;
  final String? birthday;
  final String? gender;
  final String? userAvatarData;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    RoleAvatarStore.selectUser(json['id'] as String);
    RoleAvatarStore.set(
        json['role'] as String?, json['avatar_data'] as String?);
    return UserProfile(
      id: json['id'] as String,
      phone: json['phone'] as String,
      username: json['username'] as String?,
      assistantName: json['assistant_name'] as String?,
      personality: json['personality'] as String?,
      role: json['role'] as String?,
      onboardingComplete: json['onboarding_complete'] as bool,
      companionSelectionComplete:
          json['companion_selection_complete'] as bool? ?? true,
      roleId: json['role_id'] as String?,
      birthday: json['birthday'] as String?,
      gender: json['gender'] as String?,
      userAvatarData: json['user_avatar_data'] as String?,
    );
  }
}

class AuthResult {
  const AuthResult({required this.accessToken, required this.user});

  final String accessToken;
  final UserProfile user;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        accessToken: json['access_token'] as String,
        user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
      );
}

class ProfileOptions {
  const ProfileOptions(
      {required this.personalities,
      required this.roles,
      this.roleDetails = const []});

  final List<String> personalities;
  final List<String> roles;
  final List<RoleOption> roleDetails;

  factory ProfileOptions.fromJson(Map<String, dynamic> json) => ProfileOptions(
        personalities: List<String>.from(json['personalities'] as List),
        roles: List<String>.from(json['roles'] as List),
        roleDetails: (json['role_details'] as List? ?? [])
            .map((item) =>
                RoleOption.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

class RoleOption {
  const RoleOption(
      {required this.id,
      required this.name,
      required this.builtin,
      this.nickname,
      this.roleType,
      this.personality,
      String? speakingStyle,
      String? background,
      this.prompt = '',
      this.avatarData,
      this.avatarAsset,
      this.sourcePublicationId,
      this.voiceSourceId,
      this.hasVoice = true,
      this.hasClonedVoice = false,
      this.description = '',
      this.openingLine = '',
      this.conversationId,
      this.lastMessage,
      this.lastMessageAt,
      this.categories = const ['陪伴', '朋友'],
      this.traits = const ['善于倾听', '陪伴聊天'],
      this.messageCount = 0,
      this.pinned = false,
      this.muted = false,
      this.unreadCount = 0,
      this.archived = false})
      : _speakingStyle = speakingStyle,
        _background = background;

  final String id;
  final String name;
  final bool builtin;
  final String? nickname;
  final String? roleType;
  final String? personality;
  final String? _speakingStyle, _background;
  String get speakingStyle => _speakingStyle ?? personality ?? '温柔体贴';
  String get background => _background ?? prompt;
  List<String> get personalityTags => traits;
  String get relationship => typeLabel;
  String get displayName => nickname ?? name;
  String get typeLabel => roleType ?? (builtin ? name : '自定义角色');
  String get cardDescription => [typeLabel.trim(), description.trim()]
      .where((part) => part.isNotEmpty)
      .join(' · ');
  final String prompt;
  final String? avatarData;
  final String? avatarAsset, sourcePublicationId;
  final String? voiceSourceId;
  final bool hasVoice;
  final bool hasClonedVoice;
  final String description;
  final String openingLine;
  final String? conversationId;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final List<String> categories;
  final List<String> traits;
  final int messageCount;
  final bool pinned, muted;
  final bool archived;

  factory RoleOption.fromJson(Map<String, dynamic> json) {
    final role = RoleOption(
      id: json['id'] as String,
      name: json['name'] as String,
      builtin: json['builtin'] as bool,
      nickname:
          json['character_name'] as String? ?? json['nickname'] as String?,
      roleType: json['relationship'] as String? ?? json['role_type'] as String?,
      personality: json['personality'] as String?,
      speakingStyle: json['speaking_style'] as String?,
      background: json['background'] as String?,
      prompt: json['prompt'] as String? ?? '',
      avatarData: json['avatar_data'] as String?,
      avatarAsset: _avatarAsset(json['avatar_asset'] as String?),
      sourcePublicationId: json['source_publication_id'] as String?,
      voiceSourceId: json['voice_source_id'] as String?,
      hasVoice: json['has_voice'] as bool? ?? true,
      hasClonedVoice: json['has_cloned_voice'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      openingLine: json['opening_line'] as String? ?? '',
      conversationId: json['conversation_id'] as String?,
      lastMessage: json['last_message'] as String?,
      lastMessageAt:
          DateTime.tryParse(json['last_message_at'] as String? ?? ''),
      unreadCount: json['unread_count'] as int? ?? 0,
      pinned: json['pinned'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
      muted: json['muted'] as bool? ?? false,
      categories:
          List<String>.from(json['categories'] as List? ?? ['陪伴', '朋友']),
      traits: List<String>.from(json['personality_tags'] as List? ??
          json['traits'] as List? ??
          ['善于倾听', '陪伴聊天']),
      messageCount: json['message_count'] as int? ?? 0,
    );
    RoleAvatarStore.set(role.name, role.avatarData, asset: role.avatarAsset);
    return role;
  }
}

String? _avatarAsset(String? value) =>
    roleAvatarFiles.contains(value) ? 'assets/images/$value' : null;
