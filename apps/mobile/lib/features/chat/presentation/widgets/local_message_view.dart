import 'package:bingo/features/chat/presentation/widgets/bubble_message_menu.dart';
import 'dart:async';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/message_presentation_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared menu and presentation for both human and AI messages in either chat.
class LocalMessageView extends StatefulWidget {
  const LocalMessageView(
      {required this.account,
      required this.messageKey,
      required this.text,
      required this.isUser,
      required this.builder,
      this.onReply,
      this.beforePlayback,
      super.key});
  final String account, messageKey, text;
  final bool isUser;
  final Widget Function(Widget? voice) builder;
  final VoidCallback? onReply;
  final Future<void> Function()? beforePlayback;
  @override
  State<LocalMessageView> createState() => _LocalMessageViewState();
}

class _LocalMessageViewState extends State<LocalMessageView>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late MessagePresentationStore store;
  static String? _playbackOwner;
  String get owner => '${widget.account}:${widget.messageKey}';
  bool playing = false, failed = false;
  late final pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  static const device = MethodChannel('bingo/device_tools');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bind();
  }

  void _bind() {
    store = MessagePresentationStore.forAccount(widget.account);
    store.addListener(_changed);
    unawaited(store.load().then((_) => _changed()).catchError((Object _) {
      if (mounted) setState(() => failed = true);
    }));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant LocalMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      store.removeListener(_changed);
      _stop();
      _bind();
    }
  }

  void _stop() {
    if (_playbackOwner == owner) {
      _playbackOwner = null;
      unawaited(device
          .invokeMethod<void>('stopPreviewAudio')
          .catchError((Object _) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  @override
  void dispose() {
    _stop();
    store.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    pulse.dispose();
    super.dispose();
  }

  Future<void> _update(Map<String, dynamic> values) async {
    try {
      await store.update(widget.messageKey, values);
    } catch (_) {
      if (mounted) showCenterToast(context, '无法保存本机消息设置，请重试');
    }
  }

  String get _transcript =>
      store.item(widget.messageKey)['transcript'] as String? ?? widget.text;

  Future<void> _menu(LongPressStartDetails details) async {
    unawaited(HapticFeedback.lightImpact());
    unawaited(SystemSound.play(SystemSoundType.click));
    final voice = store.item(widget.messageKey)['voice'] == true;
    final transcriptVisible =
        store.item(widget.messageKey)['transcript_visible'] == true;
    final box = context.findRenderObject() as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final action = await showBubbleMessageMenu(context,
        anchor: anchor,
        pressPosition: details.globalPosition,
        actions: [
          if (widget.onReply != null)
            const BubbleMessageAction('reply', '引用回复', Icons.reply_rounded),
          if (voice)
            BubbleMessageAction('transcribe',
                transcriptVisible ? '取消转文字' : '转文字', Icons.text_fields_rounded),
          const BubbleMessageAction('copy', '复制', Icons.copy_rounded),
          const BubbleMessageAction(
              'delete', '删除', Icons.delete_outline_rounded),
        ]);
    if (!mounted) return;
    switch (action) {
      case 'reply':
        widget.onReply?.call();
      case 'transcribe':
        if (transcriptVisible) {
          await _update({'transcript_visible': false});
        } else if (store.item(widget.messageKey)['transcription_pending'] ==
            true) {
          showCenterToast(context, '语音正在后台识别，请稍后再试');
        } else if (_transcript.trim().isEmpty) {
          showCenterToast(context, '没有识别到文字');
        } else {
          await _update({'transcript_visible': true});
        }
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _transcript));
        if (mounted) showCenterToast(context, '已复制');
      case 'delete':
        _stop();
        await _update({'hidden': true});
    }
  }

  Future<void> _play() async {
    if (playing) {
      _stop();
      return;
    }
    try {
      await widget.beforePlayback?.call();
      final bytes = await store.readVoice(widget.messageKey);
      if (bytes == null || bytes.isEmpty) throw StateError('missing recording');
      if (!mounted) return;
      _playbackOwner = owner;
      setState(() => playing = true);
      pulse.repeat(reverse: true);
      await device.invokeMethod<void>('playPreviewAudio', bytes);
    } catch (_) {
      if (mounted) showCenterToast(context, '录音暂时无法播放，请重试');
    } finally {
      if (_playbackOwner == owner) _playbackOwner = null;
      if (mounted) {
        pulse.stop();
        setState(() => playing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!store.ready) {
      if (!failed) return const SizedBox.shrink();
      return TextButton(
          onPressed: () {
            setState(() => failed = false);
            unawaited(
                store.load().then((_) => _changed()).catchError((Object _) {
              if (mounted) setState(() => failed = true);
            }));
          },
          child: const Text('本机消息设置加载失败，点击重试'));
    }
    final data = store.item(widget.messageKey);
    if (data['hidden'] == true) return const SizedBox.shrink();
    Widget? voice;
    if (data['voice'] == true) {
      final seconds = ((data['duration_ms'] as num? ?? 1000) / 1000).ceil();
      voice = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: '语音消息，$seconds 秒',
            button: true,
            child: GestureDetector(
              onTap: _play,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: (92 + seconds * 3).clamp(115, 190).toDouble(),
                height: 32,
                child: Row(children: [
                  Icon(playing ? Icons.stop_rounded : Icons.volume_up_rounded,
                      size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                      child: AnimatedBuilder(
                    animation: pulse,
                    builder: (context, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                          12,
                          (i) => Container(
                                width: 2.5,
                                height: playing
                                    ? 5 +
                                        ((i % 3 + 1) * 5) *
                                            (.35 + pulse.value * .65)
                                    : 5 + (i % 3) * 5,
                                decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: .65),
                                    borderRadius: BorderRadius.circular(3)),
                              )),
                    ),
                  )),
                  const SizedBox(width: 9),
                  Text('$seconds″', style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
          ),
          if (data['transcript_visible'] == true)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_transcript,
                    style: const TextStyle(fontSize: 14, height: 1.45))),
        ],
      );
    }

    return GestureDetector(
        onLongPressStart: _menu,
        behavior: HitTestBehavior.translucent,
        child: widget.builder(voice));
  }
}
