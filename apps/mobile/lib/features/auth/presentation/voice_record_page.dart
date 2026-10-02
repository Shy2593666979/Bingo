import 'dart:async';
import 'dart:typed_data';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const voiceReadingText = '今天的阳光很温暖，窗外的树叶轻轻摇动。'
    '我想用自己的声音，和你分享生活里的小事。'
    '开心的时候，我们一起笑；遇到困难的时候，也可以慢慢说。'
    '不用着急，每一天都有新的可能。希望这段声音，能带给你一点温暖和陪伴。';

Uint8List recordingWav(Uint8List pcm) {
  final bytes = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  header.setUint32(4, 36 + pcm.length, Endian.little);
  bytes.setRange(8, 16, 'WAVEfmt '.codeUnits);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 32000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  header.setUint32(40, pcm.length, Endian.little);
  bytes.setRange(44, bytes.length, pcm);
  return bytes;
}

class VoiceRecordPage extends StatefulWidget {
  const VoiceRecordPage({super.key});

  @override
  State<VoiceRecordPage> createState() => _VoiceRecordPageState();
}

class _VoiceRecordPageState extends State<VoiceRecordPage>
    with WidgetsBindingObserver {
  static const _device = MethodChannel('bingo/device_tools');
  static const _audio = EventChannel('bingo/audio_stream');
  BytesBuilder _buffer = BytesBuilder(copy: false);
  StreamSubscription<dynamic>? _subscription;
  Uint8List? _recorded;
  bool _recording = false;
  bool _busy = false;
  bool _playing = false;
  bool _consent = false;
  int _byteCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_recording) unawaited(_stop());
      unawaited(_device.invokeMethod<void>('stopPreviewAudio'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_device.invokeMethod<void>('stopAudioCapture'));
    unawaited(_device.invokeMethod<void>('stopPreviewAudio'));
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _recording) return;
    setState(() {
      _busy = true;
      _recorded = null;
      _byteCount = 0;
    });
    _buffer = BytesBuilder(copy: false);
    try {
      await _device.invokeMethod<void>('stopPreviewAudio');
      _subscription = _audio.receiveBroadcastStream().listen((dynamic event) {
        if (!mounted || !_recording) return;
        final remaining = 32000 * 60 - _byteCount;
        if (remaining <= 0) return;
        final received = event as Uint8List;
        final chunk = received.length > remaining
            ? Uint8List.sublistView(received, 0, remaining)
            : received;
        _buffer.add(chunk);
        setState(() => _byteCount += chunk.length);
        if (_byteCount >= 32000 * 60) unawaited(_stop());
      }, onError: (Object error) {
        if (mounted) {
          showCenterToast(context, '录音中断，请重新录制');
          unawaited(_stop(discard: true));
        }
      });
      await _device.invokeMethod<void>('startAudioCapture');
      if (!mounted) {
        await _device.invokeMethod<void>('stopAudioCapture');
        return;
      }
      setState(() => _recording = true);
    } on PlatformException catch (error) {
      await _subscription?.cancel();
      _subscription = null;
      if (mounted) showCenterToast(context, error.message ?? '请允许使用麦克风后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop({bool discard = false}) async {
    if (!_recording || _busy) return;
    setState(() => _busy = true);
    try {
      await _device.invokeMethod<void>('stopAudioCapture');
      await _subscription?.cancel();
      _subscription = null;
      final data = _buffer.takeBytes();
      if (!mounted) return;
      if (!discard && data.length < 32000 * 15) {
        showCenterToast(context, '录音时间太短，请重新录制');
      }
      setState(() {
        _recording = false;
        _recorded = !discard && data.length >= 32000 * 15 ? data : null;
      });
    } on PlatformException {
      if (mounted) {
        setState(() {
          _recording = false;
          _recorded = null;
        });
        showCenterToast(context, '录音保存失败，请重新录制');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play() async {
    if (_playing) {
      await _device.invokeMethod<void>('stopPreviewAudio');
      return;
    }
    setState(() => _playing = true);
    try {
      await _device.invokeMethod<void>(
          'playPreviewAudio', recordingWav(_recorded!));
    } on PlatformException {
      if (mounted) showCenterToast(context, '录音播放失败，请重试');
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('录制你的声音')),
          body: DecoratedBox(
            decoration:
                const BoxDecoration(gradient: BingoPalette.softGradient),
            child: SafeArea(
                child: ListView(padding: const EdgeInsets.all(24), children: [
              const Text('让角色拥有熟悉的声音',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text('找一个安静的地方，用平时说话的语气朗读下面的文字，约需 20～30 秒。',
                  style: TextStyle(color: Color(0xFF707B78), height: 1.6)),
              const SizedBox(height: 24),
              Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: BingoPalette.line)),
                  child: const Text(voiceReadingText,
                      style: TextStyle(
                          fontSize: 19, height: 1.9, color: BingoPalette.ink))),
              const SizedBox(height: 26),
              Center(
                  child: Text(
                      '${(_byteCount / 32000).floor().toString().padLeft(2, '0')} 秒',
                      style: const TextStyle(
                          fontSize: 32,
                          color: BingoPalette.blue,
                          fontWeight: FontWeight.w700))),
              const SizedBox(height: 6),
              Center(
                  child: Text(_recording ? '正在录音，读完后点击结束' : '至少录制 15 秒，最长 60 秒',
                      style: const TextStyle(color: Color(0xFF707B78)))),
              const SizedBox(height: 22),
              FilledButton.icon(
                  onPressed: _busy ? null : (_recording ? _stop : _start),
                  icon:
                      Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                  label: Text(_recording
                      ? '结束录音'
                      : (_recorded == null ? '开始录音' : '重新录制'))),
              if (_recorded != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: _play,
                    icon: Icon(_playing
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded),
                    label: Text(_playing ? '停止回听' : '回听录音')),
                const SizedBox(height: 12),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _consent,
                    onChanged: (value) =>
                        setState(() => _consent = value ?? false),
                    title: const Text('这是我的声音，或我已获得声音本人的授权',
                        style: TextStyle(fontSize: 13))),
                FilledButton(
                    onPressed: !_consent || _busy
                        ? null
                        : () async {
                            await _device
                                .invokeMethod<void>('stopPreviewAudio');
                            if (context.mounted) {
                              Navigator.of(context).pop(_recorded);
                            }
                          },
                    child: const Text('使用这段录音复刻')),
              ],
            ])),
          ),
        ),
      );
}
