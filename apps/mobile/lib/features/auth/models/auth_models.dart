class UserProfile {
  const UserProfile({
    required this.id,
    required this.phone,
    required this.username,
    required this.assistantName,
    required this.personality,
    required this.role,
    required this.onboardingComplete,
  });

  final String id;
  final String phone;
  final String? username;
  final String? assistantName;
  final String? personality;
  final String? role;
  final bool onboardingComplete;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        phone: json['phone'] as String,
        username: json['username'] as String?,
        assistantName: json['assistant_name'] as String?,
        personality: json['personality'] as String?,
        role: json['role'] as String?,
        onboardingComplete: json['onboarding_complete'] as bool,
      );
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
  const ProfileOptions({required this.personalities, required this.roles});

  final List<String> personalities;
  final List<String> roles;

  factory ProfileOptions.fromJson(Map<String, dynamic> json) => ProfileOptions(
        personalities: List<String>.from(json['personalities'] as List),
        roles: List<String>.from(json['roles'] as List),
      );
}
