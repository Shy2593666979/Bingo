import 'package:bingo/features/chat/presentation/widgets/composer_panel_space.dart';
import 'dart:math' as math;
import 'package:bingo/core/design/chat_scene.dart';
import 'package:bingo/features/stickers/sticker_widgets.dart';
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/core/design/bingo_icon.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/message_presentation_store.dart';
import 'package:bingo/features/chat/presentation/companion_moment_page.dart';
import 'package:bingo/features/chat/presentation/widgets/companion_map.dart';
import 'package:bingo/features/chat/presentation/widgets/chat_menu_icon.dart';
import 'package:bingo/features/chat/presentation/widgets/chat_composer_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({
    required this.enabled,
    required this.onSend,
    this.onVoiceSend,
    required this.speechGateway,
    required this.onCall,
    this.onGallery,
    this.onCamera,
    this.onLocation,
    this.onMoment,
    this.textController,
    this.groupMenu = false,
    this.hintText = '输入消息',
    this.referenceStyle = false,
    this.initialVoiceMode = true,
    this.reserveKeyboardSpace = false,
    this.partyMode = false,
    this.darkSurface = false,
    super.key,
  });

  final bool enabled;
  final ValueChanged<String> onSend;
  final Future<void> Function(RecordedVoice voice)? onVoiceSend;
  final SpeechGateway speechGateway;
  final VoidCallback onCall;
  final VoidCallback? onGallery;
  final VoidCallback? onCamera;
  final VoidCallback? onLocation;
  final ValueChanged<CompanionMoment>? onMoment;
  final TextEditingController? textController;
  final bool groupMenu;
  final String hintText;
  final bool referenceStyle,
      initialVoiceMode,
      reserveKeyboardSpace,
      partyMode,
      darkSurface;

  @override
  State<MessageInput> createState() => MessageInputState();
}

class MessageInputState extends State<MessageInput> {
  static const _deviceChannel = MethodChannel('bingo/device_tools');
  static const _audioChannel = EventChannel('bingo/audio_stream');
  static const _bytesPerSecond = 16000 * 2;
  static const _minimumAudioBytes = _bytesPerSecond * 600 ~/ 1000;

  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  final _composerTapRegionGroup = Object();
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
    _controller = widget.textController ?? TextEditingController();
    _voiceMode = widget.initialVoiceMode;
    _focusNode.addListener(_handleFocusChanged);
    _controller.addListener(_handleTextChanged);
  }

  bool get panelOpen => _showMore || _showStickers;

  bool dismissPanels() {
    if (!mounted || !panelOpen) return false;
    setState(() {
      _showMore = false;
      _showStickers = false;
    });
    return true;
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) dismissPanels();
  }

  void _handleTextChanged() {
    if (!mounted) return;
    setState(() {
      if (_controller.text.trim().isNotEmpty) {
        _showMore = false;
      }
    });
  }

  /// Insert without sending or discarding the existing draft.
  void insertText(String text) {
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : _controller.text.length;
    _controller.value = TextEditingValue(
        text: _controller.text.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length));
    focusTextInput();
  }

  /// Avatar mentions can switch back from voice, emoji or the expanded menu.
  void focusTextInput() {
    setState(() {
      _voiceMode = false;
      _showMore = false;
      _showStickers = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
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
    if (widget.textController == null) _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _controller.text.trim();
    if (!widget.enabled || content.isEmpty) return;
    widget.onSend(content);
    _controller.clear();
    _focusNode.requestFocus();
  }

  bool _showStickers = false;
  Future<void> _emoji() async {
    _focusNode.unfocus();
    setState(() {
      _showStickers = !_showStickers;
      _showMore = false;
      _voiceMode = false;
    });
  }

  void _toggleVoiceMode() {
    if (_recording || _transcribing) return;
    setState(() {
      _voiceMode = !_voiceMode;
      _showMore = false;
      _showStickers = false;
    });
    if (_voiceMode) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _hideMore() {
    if (!_showMore || !mounted) return;
    setState(() => _showMore = false);
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
    if (pcm.isEmpty ||
        (action == _VoiceReleaseAction.transcribe &&
            pcm.length < _minimumAudioBytes)) {
      _captureGeneration++;
      await _realtimeSession?.cancel();
      _realtimeSession = null;
      _pendingRealtimeAudio.clear();
      _removeVoiceOverlay();
      _showVoiceError('说话时间太短');
      return;
    }

    // Release the composer before final ASR; the controller owns this work now.
    if (action == _VoiceReleaseAction.send && widget.onVoiceSend != null) {
      final wav = _pcmToWav(pcm);
      final speech = widget.speechGateway;
      final realtimeStart = _realtimeStartOperation;
      _realtimeSession = null;
      // A late realtime connection must still receive this recording's buffer.
      if (mounted) {
        setState(() => _transcribing = false);
        _removeVoiceOverlay();
        final voice =
            RecordedVoice('', wav, pcm.length * 1000 ~/ _bytesPerSecond,
                transcribe: () async {
          final realtime = await realtimeStart;
          if (realtime != null) {
            try {
              return await realtime.finish();
            } catch (_) {/* Fall back to file ASR. */}
          }
          return speech.transcribe(wav);
        });
        unawaited(widget.onVoiceSend!(voice).catchError((Object error) {
          if (mounted) _showVoiceError('语音发送失败，请重试');
        }));
      }
      return;
    }

    if (mounted) {
      setState(() => _transcribing = true);
      _voiceOverlay?.markNeedsBuild();
    }
    try {
      var text = '';
      try {
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
      } catch (_) {
        if (action != _VoiceReleaseAction.send || widget.onVoiceSend == null) {
          rethrow;
        }
      }
      text = text.trim();
      if (action == _VoiceReleaseAction.transcribe && text.isEmpty) {
        _removeVoiceOverlay();
        _showVoiceError('没有识别到文字，无法发送');
      } else if (mounted && action == _VoiceReleaseAction.transcribe) {
        setState(() {
          _reviewText = text;
          _transcribing = false;
        });
        _voiceOverlay?.markNeedsBuild();
      } else if (mounted) {
        setState(() => _transcribing = false);
        _removeVoiceOverlay();
        final sendVoice = widget.onVoiceSend;
        if (sendVoice == null) {
          widget.onSend(text);
        } else {
          unawaited(sendVoice(RecordedVoice(
                  text, _pcmToWav(pcm), pcm.length * 1000 ~/ _bytesPerSecond))
              .catchError((Object error) {
            if (mounted) _showVoiceError('语音发送失败，请重试');
          }));
        }
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

  void _openMore() {
    _focusNode.unfocus();
    setState(() {
      _showMore = !_showMore;
      _showStickers = false;
    });
    if (_showMore && widget.onLocation != null) {
      unawaited(prewarmCompanionMap());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final skin = AppearanceScope.skin(context);
    final showSend = _controller.text.trim().isNotEmpty;
    final voiceLabel = _transcribing
        ? '正在转文字…'
        : _recording
            ? switch (_releaseAction) {
                _VoiceReleaseAction.cancel => '松开取消',
                _VoiceReleaseAction.transcribe => '松开转文字',
                _VoiceReleaseAction.send => '松开发送',
              }
            : '按住说话';
    final keyboardInset = widget.reserveKeyboardSpace
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    final Widget panel = _showStickers
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: StickerPanel(
                enabled: widget.enabled,
                onSend: (sticker) => widget.onSend(sticker.encode())))
        : _showMore
            ? _MoreActionsPanel(
                groupMenu: widget.groupMenu,
                onMoment: (kind) {
                  _hideMore();
                  widget.onMoment?.call(kind);
                },
                onGallery: () {
                  _hideMore();
                  widget.onGallery?.call();
                },
                onCamera: () {
                  _hideMore();
                  widget.onCamera?.call();
                },
                onLocation: () {
                  _hideMore();
                  widget.onLocation?.call();
                },
                onCall: () {
                  _hideMore();
                  widget.onCall();
                })
            : const SizedBox.shrink();
    final dark = widget.darkSurface;
    final refInk = dark ? const Color(0xFFF2F0F7) : BingoPalette.ink;
    final refMuted = dark ? const Color(0xFF9EA5C0) : ChatScene.muted;
    final refFieldBg =
        dark ? const Color(0xFF232940) : const Color(0xFFF2F6FA);
    final refAccent =
        dark ? const Color(0xFFA78BFA) : BingoPalette.primary;
    final barContent = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(widget.referenceStyle ? 8 : 12, 5,
            widget.referenceStyle ? 8 : 12, 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(widget.referenceStyle ? 0 : 7),
              decoration: BoxDecoration(
                color: widget.referenceStyle
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.97),
                borderRadius:
                    BorderRadius.circular(widget.referenceStyle ? 30 : 24),
                border: widget.referenceStyle
                    ? null
                    : Border.all(color: Colors.white),
                boxShadow: widget.referenceStyle
                    ? []
                    : const [
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
                  TapRegion(
                      groupId: _composerTapRegionGroup,
                      child: Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(
                          color: widget.referenceStyle
                              ? Colors.transparent
                              : skin.id == 'mint'
                                  ? BingoPalette.softSurface
                                  : skin.other,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: widget.enabled ? _toggleVoiceMode : null,
                          tooltip: _voiceMode ? '键盘输入' : '语音输入',
                          color: widget.referenceStyle ? refMuted : skin.accent,
                          icon: ChatComposerIcon(
                              _voiceMode
                                  ? ChatComposerSymbol.keyboard
                                  : ChatComposerSymbol.voice,
                              color: widget.referenceStyle
                                  ? refMuted
                                  : skin.accent),
                        ),
                      )),
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
                                          BingoPalette.softSurface,
                                        _VoiceReleaseAction.send =>
                                          dark
                                              ? const Color(0xFF3A2D5E)
                                              : BingoPalette.blush,
                                      }
                                    : dark
                                        ? const Color(0xFF232940)
                                        : skin.id == 'mint'
                                            ? BingoPalette.blush
                                            : skin.user,
                                border: Border.all(
                                    color: dark
                                        ? refAccent.withValues(alpha: .35)
                                        : skin.id == 'mint'
                                            ? BingoPalette.blush
                                            : skin.accent
                                                .withValues(alpha: .25)),
                                borderRadius: BorderRadius.circular(23),
                              ),
                              child: _transcribing
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: refAccent),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(voiceLabel,
                                            style: TextStyle(color: refInk)),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.mic_rounded,
                                          color: dark ? refAccent : skin.accent,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          voiceLabel,
                                          style: TextStyle(
                                            color: refInk,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                                color: widget.referenceStyle
                                    ? refFieldBg
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(25)),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                      child: TextField(
                                    onTap: () {
                                      if (_showStickers || _showMore) {
                                        setState(() {
                                          _showStickers = false;
                                          _showMore = false;
                                        });
                                      }
                                    },
                                    controller: _controller,
                                    focusNode: _focusNode,
                                    enabled: widget.enabled,
                                    minLines: 1,
                                    maxLines: 5,
                                    textInputAction: widget.partyMode
                                        ? TextInputAction.send
                                        : TextInputAction.newline,
                                    onSubmitted: widget.partyMode
                                        ? (_) => _submit()
                                        : null,
                                    style: widget.referenceStyle
                                        ? TextStyle(
                                            fontSize: 14.5,
                                            height: 1.45,
                                            color: refInk)
                                        : null,
                                    decoration: InputDecoration(
                                      hintText: widget.hintText,
                                      hintStyle: widget.referenceStyle
                                          ? TextStyle(
                                              fontSize: 14, color: refMuted)
                                          : null,
                                      filled: true,
                                      fillColor: Colors.transparent,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      disabledBorder: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 11,
                                      ),
                                    ),
                                  )),
                                  if (widget.referenceStyle &&
                                      !widget.partyMode)
                                    TapRegion(
                                        groupId: _composerTapRegionGroup,
                                        child: IconButton(
                                            tooltip: '表情',
                                            onPressed: _emoji,
                                            icon: const BingoIcon(
                                                BingoSymbol.smile,
                                                size: 25,
                                                color: BingoPalette.muted))),
                                ])),
                  ),
                  const SizedBox(width: 7),
                  TapRegion(
                    groupId: _composerTapRegionGroup,
                    child: Container(
                      width: 43,
                      height: 43,
                      decoration: BoxDecoration(
                        color: widget.referenceStyle
                            ? Colors.transparent
                            : widget.enabled
                                ? BingoPalette.softSurface
                                : colors.surfaceContainer,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        padding: widget.referenceStyle
                            ? EdgeInsets.zero
                            : const EdgeInsets.all(8),
                        onPressed: widget.partyMode
                            ? (widget.enabled && showSend ? _submit : null)
                            : (showSend
                                ? (widget.enabled ? _submit : null)
                                : (widget.enabled ? _openMore : null)),
                        tooltip: widget.partyMode
                            ? '发送'
                            : (showSend ? '发送消息' : '更多功能'),
                        disabledColor:
                            widget.referenceStyle ? Colors.white70 : null,
                        color: widget.referenceStyle
                            ? showSend
                                ? Colors.white
                                : refMuted
                            : skin.accent,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: widget.partyMode
                              ? Container(
                                  key: ValueKey('party-send-$showSend'),
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: widget.enabled && showSend
                                          ? refAccent
                                          : refFieldBg,
                                      shape: BoxShape.circle),
                                  child: ChatComposerIcon(
                                      ChatComposerSymbol.send,
                                      size: 20,
                                      color: widget.enabled && showSend
                                          ? Colors.white
                                          : refMuted))
                              : showSend
                                  ? widget.referenceStyle
                                      ? Container(
                                          key: const ValueKey('send'),
                                          width: 34,
                                          height: 34,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                              color: refAccent.withValues(
                                                  alpha:
                                                      widget.enabled ? 1 : .4),
                                              shape: BoxShape.circle),
                                          child: const ChatComposerIcon(
                                              ChatComposerSymbol.send,
                                              size: 20,
                                              color: Colors.white))
                                      : const Icon(
                                          Icons.arrow_upward_rounded,
                                          key: ValueKey('send'),
                                        )
                                  : AnimatedRotation(
                                      key: const ValueKey('more'),
                                      turns: _showMore ? 0.125 : 0,
                                      duration:
                                          const Duration(milliseconds: 180),
                                      child: ChatComposerIcon(
                                          widget.referenceStyle
                                              ? ChatComposerSymbol.addOutlined
                                              : ChatComposerSymbol.add,
                                          size: widget.referenceStyle ? 27 : 26,
                                          color: widget.referenceStyle
                                              ? refMuted.withValues(
                                                  alpha:
                                                      widget.enabled ? 1 : .4)
                                              : skin.accent),
                                    ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (keyboardInset > 0 || MediaQuery.disableAnimationsOf(context))
              ComposerPanelSpace(
                  key: const ValueKey('composer-panel-space'),
                  keyboardInset: keyboardInset,
                  child: panel)
            else
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.topCenter,
                curve: Curves.easeOutCubic,
                child: ComposerPanelSpace(
                    key: const ValueKey('composer-panel-space'),
                    keyboardInset: keyboardInset,
                    child: panel),
              ),
          ],
        ),
      ),
    );
    return TapRegion(
        groupId: _composerTapRegionGroup,
        onTapOutside: (_) {
          dismissPanels();
          _focusNode.unfocus();
        },
        child: dark
            ? Container(
                decoration: const BoxDecoration(
                    color: Color(0xFF1A1F31),
                    border:
                        Border(top: BorderSide(color: Color(0xFF282E46)))),
                child: barContent)
            : ChatGlass(bottom: true, child: barContent));
  }
}

class _MoreActionsPanel extends StatelessWidget {
  const _MoreActionsPanel({
    required this.onGallery,
    required this.onLocation,
    required this.onCamera,
    required this.onCall,
    required this.onMoment,
    this.groupMenu = false,
  });

  final bool groupMenu;
  final VoidCallback onGallery;
  final VoidCallback onLocation;
  final VoidCallback onCamera;
  final VoidCallback onCall;
  final ValueChanged<CompanionMoment> onMoment;

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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _MoreAction(
              icon: ChatMenuSymbol.photo,
              label: groupMenu ? '照片' : '相册',
              onTap: onGallery,
            ),
            _MoreAction(
              icon: ChatMenuSymbol.camera,
              label: '相机',
              onTap: onCamera,
            ),
            _MoreAction(
              icon: ChatMenuSymbol.call,
              label: '电话',
              onTap: onCall,
            ),
            _MoreAction(
                icon: ChatMenuSymbol.point, label: '位置', onTap: onLocation),
          ],
        ),
        if (!groupMenu) ...[
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final kind in CompanionMoment.values)
              _MoreAction(
                  icon: kind.icon,
                  label: kind.title,
                  onTap: () => onMoment(kind)),
          ]),
        ]
      ]),
    );
  }
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final ChatMenuSymbol icon;
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
                color: BingoPalette.chatMenuSurface,
                border: Border.all(color: BingoPalette.chatMenuBorder),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(child: ChatMenuIcon(symbol: icon)),
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

const _voiceAccent = BingoPalette.primary;

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
                activeColor: BingoPalette.blush,
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
            color: _voiceAccent,
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
          painter: const _BubbleTailPainter(_voiceAccent),
        ),
      ],
    );
  }
}

class _VoiceWaveform extends StatefulWidget {
  const _VoiceWaveform({required this.levels});
  final List<double> levels;
  @override
  State<_VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<_VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();
  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _motion,
        builder: (context, _) => Row(
          key: const ValueKey('recording-waveform'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.levels.length; i++)
              Container(
                width: 3,
                height: 7 +
                    widget.levels[i] * 30 +
                    (1 + math.sin(_motion.value * math.pi * 2 + i * .75)) * 5,
                margin: const EdgeInsets.symmetric(horizontal: 1.4),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99)),
              ),
          ],
        ),
      );
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
                      color: _voiceAccent,
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
                    painter: const _BubbleTailPainter(_voiceAccent),
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
