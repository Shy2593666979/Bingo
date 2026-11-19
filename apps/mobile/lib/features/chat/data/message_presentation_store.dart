import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RecordedVoice {
  const RecordedVoice(this.text, this.wav, this.durationMs, {this.transcribe});
  final String text;
  final Uint8List wav;
  final int durationMs;
  final Future<String> Function()? transcribe;
  Future<RecordedVoice> resolve() async {
    if (transcribe == null) return this;
    try {
      return RecordedVoice((await transcribe!()).trim(), wav, durationMs);
    } catch (_) {
      return RecordedVoice('', wav, durationMs);
    }
  }

  String get modelQuery =>
      '用户发送的语音转文字后：${text.trim().isEmpty ? '（未识别到文字）' : text.trim()}';
}

/// Display-only metadata. Never sent to the model or used to erase history.
class MessagePresentationStore extends ChangeNotifier {
  MessagePresentationStore._(this.account);
  static const channel = MethodChannel('bingo/message_presentation');
  @visibleForTesting
  static bool platformAvailable = Platform.isAndroid;
  static final _accounts = <String, MessagePresentationStore>{};
  static MessagePresentationStore forAccount(String account) =>
      _accounts.putIfAbsent(account, () => MessagePresentationStore._(account));
  @visibleForTesting
  static void resetMemory() => _accounts.clear();
  final String account;
  final _items = <String, Map<String, dynamic>>{};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool ready = false;
  String _canonical(String key) => _items[key]?['alias'] as String? ?? key;
  Map<String, dynamic> item(String key) => _items[_canonical(key)] ?? const {};
  Future<void> alias(String from, String to) =>
      update(to, {'alias': _canonical(from)});

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    if (!platformAvailable) {
      ready = true;
      return;
    }
    try {
      final raw =
          await channel.invokeMethod<String>('load', {'account': account});
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _items.addAll(decoded
            .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map))));
      }
      ready = true;
      notifyListeners();
    } on MissingPluginException {
      // Unsupported platforms still display text; Android persists metadata.
      ready = true;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<void> update(String key, Map<String, dynamic> values) async {
    await load();
    key = _canonical(key);
    final operation = _writes.then((_) async {
      final previous = _items[key];
      _items[key] = {...?previous, ...values};
      try {
        await channel.invokeMethod<void>(
            'save', {'account': account, 'data': jsonEncode(_items)});
      } catch (_) {
        if (previous == null) {
          _items.remove(key);
        } else {
          _items[key] = previous;
        }
        rethrow;
      }
      notifyListeners();
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> saveVoice(String key, RecordedVoice voice) async {
    await channel.invokeMethod<void>(
        'writeVoice', {'account': account, 'key': key, 'bytes': voice.wav});
    await update(key, {
      'voice': true,
      'transcript': voice.text.trim(),
      'duration_ms': voice.durationMs,
      'transcript_visible': false,
      'transcription_pending': voice.transcribe != null
    });
  }

  Future<void> finishTranscription(String key, RecordedVoice voice) =>
      update(key, {
        'transcript': voice.text,
        'transcription_pending': false,
      });

  Future<Uint8List?> readVoice(String key) => channel.invokeMethod<Uint8List>(
      'readVoice', {'account': account, 'key': _canonical(key)});
}
