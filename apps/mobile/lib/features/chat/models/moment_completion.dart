class MomentCompletion {
  const MomentCompletion(
      {required this.userId,
      required this.conversationId,
      required this.feature,
      required this.summary,
      required this.sessionId});

  final String userId;
  final String conversationId;
  final String feature;
  final String summary;
  final String sessionId;
}
