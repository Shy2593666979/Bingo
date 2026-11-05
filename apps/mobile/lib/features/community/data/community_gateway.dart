import 'package:bingo/features/auth/models/auth_models.dart';

class CommunityShare {
  const CommunityShare(
      {required this.id,
      required this.name,
      required this.introduction,
      required this.authorName,
      required this.createdAt,
      this.avatarAsset = 'bingo_logo.png',
      this.hasAvatar = false,
      this.hasImages = false,
      this.mine = false,
      this.favorite = false,
      this.liked = false,
      this.status = 'published',
      this.installedRoleId,
      this.parentShareId,
      this.installCount = 0,
      this.favoriteCount = 0,
      this.likeCount = 0,
      this.commentCount = 0,
      this.imageCount = 0,
      this.traits = const [],
      this.categories = const [],
      this.roleType,
      this.personality,
      this.speakingStyle,
      this.title = '',
      this.shareTags = const [],
      this.persona});
  final String title;
  final List<String> shareTags;
  final String id, name, introduction, authorName, status, avatarAsset;
  final DateTime createdAt;
  final bool hasAvatar, hasImages, mine, favorite, liked;
  final String? installedRoleId, parentShareId, roleType, personality;
  final String? speakingStyle;
  final int installCount, favoriteCount, likeCount, commentCount, imageCount;
  int get popularityScore => likeCount + favoriteCount + commentCount;
  final List<String> traits, categories;
  final Map<String, dynamic>? persona;
  factory CommunityShare.fromJson(Map<String, dynamic> json) => CommunityShare(
      id: json['id'] as String,
      name: json['name'] as String,
      introduction: json['introduction'] as String,
      title: json['title'] as String? ?? '',
      shareTags: List<String>.from(json['share_tags'] as List? ?? []),
      authorName: json['author_name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String? ?? 'published',
      avatarAsset: json['avatar_asset'] as String? ?? 'bingo_logo.png',
      hasAvatar: json['has_avatar'] == true,
      hasImages: json['has_images'] == true,
      mine: json['is_mine'] == true,
      favorite: json['is_favorite'] == true,
      liked: json['is_liked'] == true,
      likeCount: json['like_count'] as int? ?? 0,
      commentCount: json['comment_count'] as int? ?? 0,
      imageCount: json['image_count'] as int? ?? 0,
      installedRoleId: json['installed_role_id'] as String?,
      parentShareId: json['parent_share_id'] as String?,
      roleType: json['relationship'] as String? ?? json['role_type'] as String?,
      personality: json['personality'] as String?,
      speakingStyle:
          json['speaking_style'] as String? ?? json['personality'] as String?,
      installCount: json['install_count'] as int? ?? 0,
      favoriteCount: json['favorite_count'] as int? ?? 0,
      traits: List<String>.from(
          json['personality_tags'] as List? ?? json['traits'] as List? ?? []),
      categories: List<String>.from(json['categories'] as List? ?? []),
      persona: json['persona'] == null
          ? null
          : Map<String, dynamic>.from(json['persona'] as Map));
}

class CommunityPageResult {
  const CommunityPageResult(this.items, this.nextOffset, [this.total]);
  final List<CommunityShare> items;
  final int? nextOffset;
  final int? total;
}

abstract interface class CommunityGateway {
  Future<CommunityPageResult> listCommunity(
      {String query = '',
      String scope = 'all',
      String sort = 'latest',
      int offset = 0});
  Future<CommunityShare> getCommunityShare(String id);
  Future<CommunityShare> publishCompanion(
      {required String roleId,
      required String introduction,
      required String requestId,
      List<String> images = const []});
  Future<RoleOption> installCompanion(String id);
  Future<CommunityShare> favoriteCompanion(String id, bool favorite);
  Future<void> withdrawCompanion(String id);
  Future<void> reportCompanion(String id, String reason);
  String communityAvatarUrl(String id);
  String communityImageUrl(String id, int index);
  String? get communityAccessToken;
}

class CommunityComment {
  const CommunityComment(
      {required this.id,
      required this.authorName,
      required this.content,
      required this.createdAt,
      this.mine = false});
  final String id, authorName, content;
  final DateTime createdAt;
  final bool mine;
  factory CommunityComment.fromJson(Map<String, dynamic> value) =>
      CommunityComment(
          id: value['id'] as String,
          authorName: value['author_name'] as String,
          content: value['content'] as String,
          createdAt: DateTime.parse(value['created_at'] as String),
          mine: value['is_mine'] == true);
}

abstract interface class CommunityEngagementGateway {
  Future<CommunityShare> likeCompanion(String id, bool liked);
  Future<List<CommunityComment>> listCompanionComments(String id,
      {int offset = 0});
  Future<CommunityComment> commentCompanion(
      String id, String content, String requestId);
  Future<void> deleteCompanionComment(String id, String commentId);
}

abstract interface class CommunityPublishingGateway {
  Future<CommunityShare> publishCompanionDetail(
      {required String roleId,
      required String introduction,
      required String requestId,
      String title = '',
      List<String> shareTags = const [],
      List<String> images = const []});
}
