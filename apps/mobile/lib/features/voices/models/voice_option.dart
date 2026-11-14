class VoiceOption {
  const VoiceOption(
      {required this.id,
      required this.name,
      this.description = '',
      this.gender = 'unknown',
      this.scope = 'private',
      this.status = 'draft',
      this.editable = false,
      this.hasAudio = false});
  final String id, name, description, gender, scope, status;
  final bool editable, hasAudio;
  bool get ready => hasAudio && status != 'failed';
  String get genderLabel =>
      switch (gender) { 'male' => '男声', 'female' => '女声', _ => '不限' };
  String get statusLabel => switch (status) {
        'ready' => description.isEmpty ? genderLabel : description,
        'processing' => '正在复刻',
        'failed' => '复刻失败，可重新录制',
        _ => '尚未录制声音',
      };
  factory VoiceOption.fromJson(Map<String, dynamic> json) => VoiceOption(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      gender: json['gender'] as String? ?? 'unknown',
      scope: json['scope'] as String? ?? 'private',
      status: json['status'] as String? ?? 'draft',
      editable: json['editable'] == true,
      hasAudio: json['has_audio'] == true);
}
