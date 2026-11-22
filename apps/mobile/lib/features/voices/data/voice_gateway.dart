import 'dart:typed_data';
import 'package:bingo/features/voices/models/voice_option.dart';

abstract interface class StreamingVoiceGateway {
  Stream<Uint8List> streamVoicePreview(String id);
  void stopVoicePreview();
}

abstract interface class VoiceGateway {
  Future<List<VoiceOption>> listVoices({String? scope, String? gender});
  Future<VoiceOption> createVoice(
      {required String name,
      String description = '',
      String gender = 'unknown'});
  Future<VoiceOption> updateVoice(String id,
      {required String name,
      String description = '',
      String gender = 'unknown'});
  Future<void> deleteVoice(String id);
  Future<String> cloneVoice(String id, Uint8List audio);
  Future<Map<String, dynamic>> voiceJob(String id);
  Future<Uint8List> previewVoice(String id);
  Future<void> assignRoleVoice(String roleId, String voiceId);
}
