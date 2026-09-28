import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RealtimeCallPage extends StatefulWidget {
  const RealtimeCallPage({
    required this.gateway,
    required this.assistantName,
    required this.assistantRole,
    required this.showCaptions,
    this.conversationId,
    this.callId,
    super.key,
  });

  final RealtimeCallGateway gateway;
  final String assistantName;
  final String? assistantRole;
  final String? conversationId;
  final String? callId;
  final bool showCaptions;

  @override
  State<RealtimeCallPage> createState() => _RealtimeCallPageState();
}

class _RealtimeCallPageState extends State<RealtimeCallPage> {
  static const _deviceChannel = MethodChannel('bingo/device_tools');
  static const _audioChannel = EventChannel('bingo/audio_stream');

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<dynamic>? _audioSubscription;
  Timer? _durationTimer;
  final Completer<void> _serverEnded = Completer<void>();
  Duration _duration = Duration.zero;
  String _status = '正在连接…';
  String _userTranscript = '';
  String _assistantTranscript = '';
  String? _conversationId;
  bool _muted = false;
  bool _speaker = true;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      final socket = await widget.gateway.connectRealtimeCall(
        conversationId: widget.conversationId,
        callId: widget.callId,
      );
      if (!mounted) {
        await socket.close();
        return;
      }
      _socket = socket;
      _socketSubscription = socket.listen(
        _onSocketData,
        onError: (Object error) => _fail('连接已断开，请稍后重试'),
        onDone: () {
          if (!_ending) _fail('通话连接已结束');
        },
        cancelOnError: true,
      );
    } on Object catch (error) {
      _fail(error is ApiException ? error.message : '无法连接实时通话服务');
    }
  }

  Future<void> _onSocketData(dynamic data) async {
    if (data is List<int>) {
      await _deviceChannel.invokeMethod<void>(
        'playCallAudio',
        Uint8List.fromList(data),
      );
      return;
    }
    if (data is! String) return;
    final event = jsonDecode(data) as Map<String, dynamic>;
    switch (event['type']) {
      case 'ready':
        _conversationId = event['conversation_id'] as String?;
        await _startAudio();
        _socket?.add(jsonEncode({'type': 'client_audio_ready'}));
        _durationTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _duration += const Duration(seconds: 1));
        });
        _setStatus('正在聆听');
      case 'speech_started':
        await _deviceChannel.invokeMethod<void>('clearCallAudio');
        _setStatus('正在聆听');
      case 'assistant_speaking':
        if (mounted) {
          setState(() {
            if (widget.showCaptions) _assistantTranscript = '';
            _status = '对方正在说话';
          });
        }
      case 'response_done':
        _setStatus('正在聆听');
      case 'user_transcript.delta':
        _updateTranscript(
            user: '${event['text'] ?? ''}${event['stash'] ?? ''}');
      case 'user_transcript.done':
        _updateTranscript(user: event['text'] as String? ?? '');
      case 'assistant_transcript.delta':
        _updateTranscript(
          assistant: _assistantTranscript + (event['text'] as String? ?? ''),
        );
      case 'assistant_transcript.done':
        _updateTranscript(assistant: event['text'] as String? ?? '');
      case 'error':
        _fail(event['message'] as String? ?? '实时通话发生错误');
      case 'ended':
        _conversationId =
            event['conversation_id'] as String? ?? _conversationId;
        if (!_serverEnded.isCompleted) _serverEnded.complete();
        if (!_ending) unawaited(_finish(notifyServer: false));
    }
  }

  Future<void> _startAudio() async {
    _audioSubscription = _audioChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (_muted || _ending) return;
        final socket = _socket;
        if (socket == null) return;
        if (data is Uint8List) {
          socket.add(data);
        } else if (data is List<int>) {
          socket.add(Uint8List.fromList(data));
        }
      },
      onError: (Object _) => _fail('无法读取麦克风'),
    );
    await _deviceChannel.invokeMethod<void>(
      'startCallAudio',
      {'speaker': _speaker},
    );
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  void _updateTranscript({String? user, String? assistant}) {
    if (!mounted || !widget.showCaptions) return;
    setState(() {
      if (user != null) _userTranscript = user;
      if (assistant != null) _assistantTranscript = assistant;
    });
  }

  void _fail(String message) {
    if (!mounted || _ending) return;
    setState(() => _status = message);
  }

  Future<void> _toggleSpeaker() async {
    final enabled = !_speaker;
    await _deviceChannel.invokeMethod<void>('setCallSpeaker', enabled);
    if (mounted) setState(() => _speaker = enabled);
  }

  Future<void> _finish({bool notifyServer = true}) async {
    if (_ending) return;
    _ending = true;
    _durationTimer?.cancel();
    if (notifyServer) {
      _socket?.add(jsonEncode({'type': 'hangup'}));
    }
    await _audioSubscription?.cancel();
    await _deviceChannel.invokeMethod<void>('stopCallAudio');
    if (!_serverEnded.isCompleted) {
      try {
        await _serverEnded.future.timeout(const Duration(seconds: 4));
      } on TimeoutException {
        // Return even if the connection disappears during hangup.
      }
    }
    await _socketSubscription?.cancel();
    await _socket?.close(WebSocketStatus.normalClosure);
    if (mounted) Navigator.of(context).pop(_conversationId);
  }

  @override
  void dispose() {
    _ending = true;
    _durationTimer?.cancel();
    unawaited(_audioSubscription?.cancel());
    unawaited(_socketSubscription?.cancel());
    unawaited(_deviceChannel.invokeMethod<void>('stopCallAudio'));
    unawaited(_socket?.close(WebSocketStatus.normalClosure));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (_duration.inSeconds % 60).toString().padLeft(2, '0');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_finish());
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: BingoPalette.softGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 32),
              child: Column(
                children: [
                  AssistantAvatar(
                    role: widget.assistantRole,
                    size: 116,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.assistantName,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(_status,
                      style: const TextStyle(color: Color(0xFF65716D))),
                  const SizedBox(height: 5),
                  Text('$minutes:$seconds',
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 32),
                  Expanded(
                    child: widget.showCaptions
                        ? SingleChildScrollView(
                            child: Column(
                              children: [
                                if (_userTranscript.isNotEmpty)
                                  _TranscriptCard(
                                    label: '我',
                                    text: _userTranscript,
                                  ),
                                if (_assistantTranscript.isNotEmpty)
                                  _TranscriptCard(
                                    label: widget.assistantName,
                                    text: _assistantTranscript,
                                    assistant: true,
                                  ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallAction(
                        icon:
                            _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _muted ? '取消静音' : '静音',
                        active: _muted,
                        onTap: () => setState(() => _muted = !_muted),
                      ),
                      _CallAction(
                        icon: Icons.call_end_rounded,
                        label: '挂断',
                        destructive: true,
                        onTap: () => unawaited(_finish()),
                      ),
                      _CallAction(
                        icon: _speaker
                            ? Icons.volume_up_rounded
                            : Icons.hearing_rounded,
                        label: '免提',
                        active: _speaker,
                        onTap: () => unawaited(_toggleSpeaker()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({
    required this.label,
    required this.text,
    this.assistant = false,
  });

  final String label;
  final String text;
  final bool assistant;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: assistant ? const Color(0xFFDDF4EC) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF68736F))),
          const SizedBox(height: 5),
          Text(text, style: const TextStyle(fontSize: 16, height: 1.45)),
        ],
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFE94D4D)
        : active
            ? BingoPalette.blue
            : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
              icon,
              color: destructive || active ? Colors.white : BingoPalette.ink,
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }
}
