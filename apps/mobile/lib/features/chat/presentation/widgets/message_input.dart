import 'dart:async';
import 'dart:typed_data';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({
    required this.enabled,
    required this.onSend,
    required this.speechGateway,
    required this.onCall,
    this.onGallery,
    this.onCamera,
    super.key,
  });

  final bool enabled;
  final ValueChanged<String> onSend;
  final SpeechGateway speechGateway;
  final VoidCallback onCall;
  final VoidCallback? onGallery;
  final VoidCallback? onCamera;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  static const _deviceChannel = MethodChannel('bingo/device_tools');
  static const _audioChannel = EventChannel('bingo/audio_stream');
  static const _bytesPerSecond = 16000 * 2;
  static const _minimumAudioBytes = _bytesPerSecond * 600 ~/ 1000;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  BytesBuilder _audio = BytesBuilder(copy: false);
  StreamSubscription<dynamic>? _audioSubscription;
  RealtimeTranscriptionSession? _realtimeSession;
  Future<RealtimeTranscriptionSession?>? _realtimeStartOperation;
  Future<void>? _startOperation;
  final List<Uint8List> _pendingRealtimeAudio = [];
  int _captureGeneration = 0;
  bool _voiceMode = true;
  bool _pointerDown = false;
  bool _recording = false;
  bool _transcribing = false;
  bool _showMore = false;
  double _pressX = 0;
  _VoiceReleaseAction _releaseAction = _VoiceReleaseAction.send;
  OverlayEntry? _voiceOverlay;
  String? _reviewText;
  final List<double> _audioLevels =
      List<double>.filled(19, 0.08, growable: true);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    if (!mounted) return;
    setState(() {
      if (_controller.text.trim().isNotEmpty) {
        _showMore = false;
      }
    });
  }

  @override
  void dispose() {
    _captureGeneration++;
    unawaited(_deviceChannel.invokeMethod<void>('stopAudioCapture'));
    unawaited(_audioSubscription?.cancel());
    unawaited(_realtimeSession?.cancel());
    _voiceOverlay?.remove();
    _voiceOverlay = null;
    _pendingRealtimeAudio.clear();
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _controller.text.trim();
    if (!widget.enabled || content.isEmpty) return;
    _controller.clear();
    widget.onSend(content);
    _focusNode.requestFocus();
  }

  void _toggleVoiceMode() {
    if (_recording || _transcribing) return;
    setState(() => _voiceMode = !_voiceMode);
    if (_voiceMode) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled || _transcribing || _recording) return;
    unawaited(HapticFeedback.mediumImpact());
    _pointerDown = true;
    _releaseAction = _VoiceReleaseAction.send;
    _pressX = event.position.dx;
    _reviewText = null;
    _audioLevels
      ..clear()
      ..addAll(List.filled(19, 0.08));
    _startOperation = _startCapture();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pointerDown) return;
    final distance = event.position.dx - _pressX;
    final action = distance <= -72
        ? _VoiceReleaseAction.cancel
        : distance >= 72
            ? _VoiceReleaseAction.transcribe
            : _VoiceReleaseAction.send;
    if (action != _releaseAction) {
      unawaited(HapticFeedback.selectionClick());
      setState(() => _releaseAction = action);
      _voiceOverlay?.markNeedsBuild();
    }
  }

  void _handlePointerUp(PointerEvent event) {
    if (!_pointerDown) return;
    _pointerDown = false;
    unawaited(HapticFeedback.lightImpact());
    unawaited(_finishCapture(action: _releaseAction));
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _releaseAction = _VoiceReleaseAction.cancel;
    _handlePointerUp(event);
  }

  Future<void> _startCapture() async {
    final generation = ++_captureGeneration;
    _audio = BytesBuilder(copy: false);
    _realtimeSession = null;
    _pendingRealtimeAudio.clear();
    if (mounted) {
      setState(() => _recording = true);
      _showVoiceOverlay();
    }
    final speechGateway = widget.speechGateway;
    if (speechGateway is RealtimeSpeechGateway) {
      _realtimeStartOperation = _adoptRealtime(
        _openRealtime(speechGateway as RealtimeSpeechGateway),
        generation,
      );
    } else {
      _realtimeStartOperation = Future.value(null);
    }
    try {
      _audioSubscription = _audioChannel.receiveBroadcastStream().listen(
        (data) {
          if (data is Uint8List) {
            _audio.add(data);
            _sendOrBufferRealtimeAudio(data);
            _updateAudioLevel(data);
          } else if (data is List<int>) {
            final chunk = Uint8List.fromList(data);
            _audio.add(chunk);
            _sendOrBufferRealtimeAudio(chunk);
            _updateAudioLevel(chunk);
          }
        },
        onError: (Object error) => _showVoiceError('麦克风读取失败：$error'),
      );
      await _deviceChannel.invokeMethod<void>('startAudioCapture');
    } on PlatformException catch (error) {
      _captureGeneration++;
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      await _realtimeSession?.cancel();
      _realtimeSession = null;
      _pendingRealtimeAudio.clear();
      if (mounted) {
        setState(() => _recording = false);
        _removeVoiceOverlay();
        _showVoiceError(error.message ?? '无法启动麦克风');
      }
    }
  }

  Future<RealtimeTranscriptionSession?> _openRealtime(
    RealtimeSpeechGateway gateway,
  ) async {
    try {
      return await gateway.startRealtimeTranscription();
    } on Exception {
      return null;
    }
  }

  Future<RealtimeTranscriptionSession?> _adoptRealtime(
    Future<RealtimeTranscriptionSession?> operation,
    int generation,
  ) async {
    final session = await operation;
    if (session == null) return null;
    if (generation != _captureGeneration) {
      await session.cancel();
      return null;
    }
    _realtimeSession = session;
    for (final chunk in _pendingRealtimeAudio) {
      session.addAudio(chunk);
    }
    _pendingRealtimeAudio.clear();
    return session;
  }

  void _sendOrBufferRealtimeAudio(Uint8List chunk) {
    final session = _realtimeSession;
    if (session == null) {
      _pendingRealtimeAudio.add(chunk);
    } else {
      session.addAudio(chunk);
    }
  }

  Future<void> _finishCapture({required _VoiceReleaseAction action}) async {
    await _startOperation;
    if (!_recording) {
      _removeVoiceOverlay();
      return;
    }
    await _deviceChannel.invokeMethod<void>('stopAudioCapture');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    final pcm = _audio.takeBytes();
    if (mounted) {
      setState(() {
        _recording = false;
        _releaseAction = _VoiceReleaseAction.send;
      });
    }
    if (action == _VoiceReleaseAction.cancel) {
      _captureGeneration++;
      await _realtimeSession?.cancel();
      _realtimeSession = null;
      _pendingRealtimeAudio.clear();
      _removeVoiceOverlay();
      return;
    }
    if (pcm.length < _minimumAudioBytes) {
      _captureGeneration++;
      await _realtimeSession?.cancel();
      _realtimeSession = null;
      _pendingRealtimeAudio.clear();
      _removeVoiceOverlay();
      _showVoiceError('说话时间太短');
      return;
    }

    if (mounted) {
      setState(() => _transcribing = true);
      _voiceOverlay?.markNeedsBuild();
    }
    try {
      String text;
      final realtimeSession = await _realtimeStartOperation;
      _realtimeSession = null;
      _pendingRealtimeAudio.clear();
      if (realtimeSession != null) {
        try {
          text = await realtimeSession.finish();
        } on Exception {
          text = await widget.speechGateway.transcribe(_pcmToWav(pcm));
        }
      } else {
        text = await widget.speechGateway.transcribe(_pcmToWav(pcm));
      }
      if (text.isEmpty) {
        _removeVoiceOverlay();
        _showVoiceError('没有识别到清晰的语音');
      } else if (mounted && action == _VoiceReleaseAction.transcribe) {
        setState(() {
          _reviewText = text;
          _transcribing = false;
        });
        _voiceOverlay?.markNeedsBuild();
      } else if (mounted) {
        _removeVoiceOverlay();
        widget.onSend(text);
      }
    } on ApiException catch (error) {
      _removeVoiceOverlay();
      _showVoiceError(error.message);
    } on Exception catch (error) {
      _removeVoiceOverlay();
      _showVoiceError('语音识别失败：$error');
    } finally {
      if (mounted && _reviewText == null) {
        setState(() => _transcribing = false);
      }
    }
  }

  void _updateAudioLevel(Uint8List pcm) {
    if (pcm.length < 2) return;
    final samples = ByteData.sublistView(pcm);
    var peak = 0;
    for (var offset = 0; offset + 1 < pcm.length; offset += 8) {
      final value = samples.getInt16(offset, Endian.little).abs();
      if (value > peak) peak = value;
    }
    final level = (peak / 18000).clamp(0.08, 1.0).toDouble();
    _audioLevels
      ..removeAt(0)
      ..add(level);
    _voiceOverlay?.markNeedsBuild();
  }

  void _showVoiceOverlay() {
    if (_voiceOverlay != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _voiceOverlay = OverlayEntry(
      builder: (overlayContext) {
        final reviewText = _reviewText;
        if (reviewText != null) {
          return _VoiceTranscriptReview(
            text: reviewText,
            onCancel: _cancelTranscript,
            onSend: _sendTranscript,
          );
        }
        return IgnorePointer(
          child: _VoiceRecordingOverlay(
            action: _releaseAction,
            transcribing: _transcribing,
            audioLevels: List.of(_audioLevels),
          ),
        );
      },
    );
    overlay.insert(_voiceOverlay!);
  }

  void _removeVoiceOverlay() {
    _voiceOverlay?.remove();
    _voiceOverlay = null;
  }

  void _cancelTranscript() {
    setState(() => _reviewText = null);
    _removeVoiceOverlay();
  }

  void _sendTranscript() {
    final text = _reviewText?.trim();
    setState(() => _reviewText = null);
    _removeVoiceOverlay();
    if (text != null && text.isNotEmpty && widget.enabled) {
      widget.onSend(text);
    }
  }

  Uint8List _pcmToWav(Uint8List pcm) {
    final wav = ByteData(44 + pcm.length);
    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        wav.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    wav.setUint32(4, 36 + pcm.length, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);
    wav.setUint16(22, 1, Endian.little);
    wav.setUint32(24, 16000, Endian.little);
    wav.setUint32(28, _bytesPerSecond, Endian.little);
    wav.setUint16(32, 2, Endian.little);
    wav.setUint16(34, 16, Endian.little);
    text(36, 'data');
    wav.setUint32(40, pcm.length, Endian.little);
    wav.buffer.asUint8List(44).setAll(0, pcm);
    return wav.buffer.asUint8List();
  }

  void _showVoiceError(String message) {
    if (!mounted) return;
    showCenterToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showSend = !_voiceMode && _controller.text.trim().isNotEmpty;
    final voiceLabel = _transcribing
        ? '正在转文字…'
        : _recording
            ? switch (_releaseAction) {
                _VoiceReleaseAction.cancel => '松开取消',
                _VoiceReleaseAction.transcribe => '松开转文字',
                _VoiceReleaseAction.send => '松开发送',
              }
            : '按住说话';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14205F4F),
                    blurRadius: 20,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF6F3),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: widget.enabled ? _toggleVoiceMode : null,
                      tooltip: _voiceMode ? '键盘输入' : '语音输入',
                      color: BingoPalette.blue,
                      icon: Icon(_voiceMode
                          ? Icons.keyboard_alt_rounded
                          : Icons.mic_rounded),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _voiceMode
                        ? Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _handlePointerDown,
                            onPointerMove: _handlePointerMove,
                            onPointerUp: _handlePointerUp,
                            onPointerCancel: _handlePointerCancel,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _recording
                                    ? switch (_releaseAction) {
                                        _VoiceReleaseAction.cancel =>
                                          colors.errorContainer,
                                        _VoiceReleaseAction.transcribe =>
                                          const Color(0xFFDFF4EE),
                                        _VoiceReleaseAction.send =>
                                          const Color(0xFFD7F2E8),
                                      }
                                    : const Color(0xFFCDEEE2),
                                border:
                                    Border.all(color: const Color(0xFFB8E4D5)),
                                borderRadius: BorderRadius.circular(23),
                              ),
                              child: _transcribing
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(voiceLabel),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.mic_rounded,
                                          color: BingoPalette.blue,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          voiceLabel,
                                          style: const TextStyle(
                                            color: BingoPalette.ink,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          )
                        : TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            enabled: widget.enabled,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText: '输入消息',
                              filled: true,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 11,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: widget.enabled
                          ? const Color(0xFFEEF6F3)
                          : colors.surfaceContainer,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: !widget.enabled
                          ? null
                          : showSend
                              ? _submit
                              : () {
                                  _focusNode.unfocus();
                                  setState(() => _showMore = !_showMore);
                                },
                      tooltip: showSend ? '发送消息' : '更多功能',
                      color: BingoPalette.blue,
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: child),
                        child: showSend
                            ? const Icon(
                                Icons.arrow_upward_rounded,
                                key: ValueKey('send'),
                              )
                            : AnimatedRotation(
                                key: const ValueKey('more'),
                                turns: _showMore ? 0.125 : 0,
                                duration: const Duration(milliseconds: 180),
                                child: const Icon(Icons.add_rounded),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _showMore
                  ? _MoreActionsPanel(
                      onGallery: () {
                        setState(() => _showMore = false);
                        widget.onGallery?.call();
                      },
                      onCamera: () {
                        setState(() => _showMore = false);
                        widget.onCamera?.call();
                      },
                      onCall: () {
                        setState(() => _showMore = false);
                        widget.onCall();
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreActionsPanel extends StatelessWidget {
  const _MoreActionsPanel({
    required this.onGallery,
    required this.onCamera,
    required this.onCall,
  });

  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x14205F4F), blurRadius: 20),
        ],
      ),
      child: Row(
        children: [
          _MoreAction(
            icon: Icons.photo_outlined,
            label: '相册',
            onTap: onGallery,
          ),
          const SizedBox(width: 28),
          _MoreAction(
            icon: Icons.photo_camera_outlined,
            label: '相机',
            onTap: onCamera,
          ),
          const SizedBox(width: 28),
          _MoreAction(
            icon: Icons.call_rounded,
            label: '电话',
            onTap: onCall,
          ),
        ],
      ),
    );
  }
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF6F3),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: BingoPalette.blue, size: 28),
            ),
            const SizedBox(height: 7),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

enum _VoiceReleaseAction { send, cancel, transcribe }

const _voiceGreen = Color(0xFF8EEA6A);

class _VoiceRecordingOverlay extends StatelessWidget {
  const _VoiceRecordingOverlay({
    required this.action,
    required this.transcribing,
    required this.audioLevels,
  });

  final _VoiceReleaseAction action;
  final bool transcribing;
  final List<double> audioLevels;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: const Alignment(0, -0.16),
              child: _VoiceStatusBubble(
                transcribing: transcribing,
                audioLevels: audioLevels,
              ),
            ),
            Positioned(
              left: 24,
              bottom: 142,
              child: _VoiceActionTarget(
                icon: Icons.close_rounded,
                label: '取消',
                active: action == _VoiceReleaseAction.cancel,
                activeColor: const Color(0xFFFFD9D5),
              ),
            ),
            Positioned(
              right: 24,
              bottom: 142,
              child: _VoiceActionTarget(
                icon: Icons.text_fields_rounded,
                label: '转文字',
                active: action == _VoiceReleaseAction.transcribe,
                activeColor: const Color(0xFFCFF5E8),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 116,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: action == _VoiceReleaseAction.send
                      ? Colors.white.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.elliptical(420, 92),
                  ),
                ),
                child: Text(
                  transcribing ? '正在转文字…' : '松开 发送',
                  style: const TextStyle(
                    color: BingoPalette.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceStatusBubble extends StatelessWidget {
  const _VoiceStatusBubble({
    required this.transcribing,
    required this.audioLevels,
  });

  final bool transcribing;
  final List<double> audioLevels;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 230,
          height: 108,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _voiceGreen,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 18),
            ],
          ),
          child: transcribing
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: BingoPalette.ink,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      '正在转文字',
                      style: TextStyle(
                        color: BingoPalette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : _VoiceWaveform(levels: audioLevels),
        ),
        CustomPaint(
          size: const Size(28, 16),
          painter: const _BubbleTailPainter(_voiceGreen),
        ),
      ],
    );
  }
}

class _VoiceWaveform extends StatelessWidget {
  const _VoiceWaveform({required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final level in levels)
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 3,
            height: 7 + level * 32,
            margin: const EdgeInsets.symmetric(horizontal: 1.4),
            decoration: BoxDecoration(
              color: BingoPalette.blue,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _VoiceActionTarget extends StatelessWidget {
  const _VoiceActionTarget({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: active ? 92 : 82,
          height: 72,
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(36),
          ),
          child: Icon(
            icon,
            size: 30,
            color: active ? BingoPalette.ink : Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 15,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _VoiceTranscriptReview extends StatelessWidget {
  const _VoiceTranscriptReview({
    required this.text,
    required this.onCancel,
    required this.onSend,
  });

  final String text;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.74),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 42, 24, 30),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 270),
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                    decoration: BoxDecoration(
                      color: _voiceGreen,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        text,
                        style: const TextStyle(
                          color: BingoPalette.ink,
                          fontSize: 22,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: const Size(28, 16),
                    painter: const _BubbleTailPainter(_voiceGreen),
                  ),
                ],
              ),
              const Spacer(flex: 3),
              Row(
                children: [
                  _ReviewActionButton(
                    icon: Icons.close_rounded,
                    label: '取消',
                    onTap: onCancel,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: SizedBox(
                      height: 68,
                      child: FilledButton(
                        onPressed: onSend,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: BingoPalette.ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          '发送',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewActionButton extends StatelessWidget {
  const _ReviewActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(36),
      child: SizedBox(
        width: 90,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..quadraticBezierTo(
        size.width * 0.64,
        size.height * 0.72,
        size.width * 0.5,
        size.height,
      )
      ..quadraticBezierTo(size.width * 0.36, size.height * 0.72, 0, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color;
}
