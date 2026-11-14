import 'package:bingo/core/design/bingo_page.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'dart:async';
import 'package:bingo/core/design/companion_launch_ui.dart';
import 'package:bingo/features/auth/presentation/voice_record_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/voices/data/voice_gateway.dart';
import 'package:bingo/features/voices/models/voice_option.dart';
import 'package:bingo/features/voices/presentation/voice_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VoiceEditorPage extends StatefulWidget {
  const VoiceEditorPage({required this.gateway, this.voice, super.key});
  final VoiceGateway gateway;
  final VoiceOption? voice;
  @override
  State<VoiceEditorPage> createState() => _VoiceEditorPageState();
}

class _VoiceEditorPageState extends State<VoiceEditorPage>
    with WidgetsBindingObserver {
  static const _device = MethodChannel('bingo/device_tools');
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _description;
  late String _gender;
  VoiceOption? _asset;
  bool _busy = false, _playing = false;
  String? _error, _stage;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _asset = widget.voice;
    _name = TextEditingController(text: widget.voice?.name);
    _description = TextEditingController(text: widget.voice?.description);
    _gender = widget.voice?.gender ?? 'unknown';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _generation++;
      unawaited(_stop());
    }
  }

  Future<void> _stop() =>
      _device.invokeMethod<void>('stopPreviewAudio').catchError((_) {});
  @override
  void dispose() {
    _generation++;
    unawaited(_stop());
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<VoiceOption> _saveMetadata() async {
    final value = _asset == null
        ? await widget.gateway.createVoice(
            name: _name.text.trim(),
            description: _description.text.trim(),
            gender: _gender)
        : await widget.gateway.updateVoice(_asset!.id,
            name: _name.text.trim(),
            description: _description.text.trim(),
            gender: _gender);
    _asset = value;
    return value;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final asset = await _saveMetadata();
      if (mounted) Navigator.pop(context, asset);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error is ApiException ? error.message : '保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _record() async {
    if (!_form.currentState!.validate() || _busy) return;
    _generation++;
    await _stop();
    if (!mounted) return;
    final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => const VoiceRecordPage()));
    if (!mounted || bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _stage = '正在上传录音…';
    });
    try {
      final asset = await _saveMetadata();
      final job = await widget.gateway.cloneVoice(asset.id, bytes);
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (mounted && DateTime.now().isBefore(deadline)) {
        final status = await widget.gateway.voiceJob(job);
        if (!mounted) return;
        setState(() => _stage = switch (status['stage']) {
              'uploading' => '正在准备录音…',
              'verifying' => '正在验证新音色…',
              'pending' => '录音已收到，等待处理…',
              _ => '正在复刻声音…',
            });
        if (status['status'] == 'ready') {
          final assets = await widget.gateway.listVoices();
          if (mounted) {
            setState(() {
              _asset =
                  assets.where((item) => item.id == asset.id).firstOrNull ??
                      asset;
              _stage = '音色已保存，可以试听或给搭子使用。';
            });
          }
          return;
        }
        if (status['status'] == 'failed' || status['status'] == 'cancelled') {
          throw ApiException(status['error'] as String? ?? '复刻未完成，请重新录制');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (mounted) setState(() => _stage = '任务仍在后台处理，可返回音色库查看。');
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error is ApiException ? error.message : '复刻失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    final asset = _asset;
    if (asset == null || !asset.hasAudio) return;
    final generation = ++_generation;
    final stop = _playing;
    setState(() {
      _playing = !stop;
      _error = null;
    });
    try {
      await _stop();
      if (stop) return;
      final audio = await widget.gateway.previewVoice(asset.id);
      if (!mounted || generation != _generation) return;
      await _device.invokeMethod<void>('playPreviewAudio', audio);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '试听失败，请重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _playing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
            title: Text(widget.voice == null ? '创建新音色' : '编辑音色'),
            centerTitle: true),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              BingoSection(
                  child: Row(children: [
                VoiceCover(id: _asset?.id ?? 'new-voice', size: 64),
                const SizedBox(width: 16),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('留住熟悉的声音',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w500)),
                      SizedBox(height: 6),
                      Text('独立保存，多个搭子都能使用',
                          style: TextStyle(
                              fontSize: 12, color: BingoPalette.muted)),
                    ])),
              ])),
              const SizedBox(height: 28),
              Text('音色名称',
                  style: CompanionLaunch.text(15, weight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextFormField(
                  key: const ValueKey('voice-name'),
                  controller: _name,
                  maxLength: 60,
                  decoration: const InputDecoration(
                      hintText: '给这个声音起个名字', counterText: ''),
                  validator: (value) =>
                      value?.trim().isNotEmpty == true ? null : '请填写音色名称'),
              const SizedBox(height: 24),
              Text('声音类型',
                  style: CompanionLaunch.text(15, weight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, children: [
                for (final entry in [
                  ('unknown', '不限'),
                  ('male', '男声'),
                  ('female', '女声')
                ])
                  ChoiceChip(
                      label: Text(entry.$2),
                      selected: _gender == entry.$1,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _gender = entry.$1))
              ]),
              const SizedBox(height: 24),
              Text('音色描述',
                  style: CompanionLaunch.text(15, weight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: const InputDecoration(
                      hintText: '例如：温柔、自然、语速舒缓', counterText: '')),
              const SizedBox(height: 26),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _record,
                  icon: const Icon(Icons.mic_none_rounded),
                  label: Text(_asset?.hasAudio == true ? '重新录制声音' : '录制我的声音')),
              const SizedBox(height: 8),
              Text('按引导录制 15～60 秒。音色独立保存，可供多个搭子使用。',
                  style: CompanionLaunch.text(12,
                      color: CompanionLaunch.muted, height: 1.5)),
              if (_busy)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: LinearProgressIndicator()),
              if (_stage != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_stage!)),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_asset?.hasAudio == true)
                TextButton.icon(
                    onPressed: _busy ? null : _preview,
                    icon: Icon(_playing
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded),
                    label: Text(_playing ? '停止试听' : '试听音色')),
            ])),
        bottomNavigationBar: BingoActionBar(
            child: FilledButton(
                onPressed: _busy ? null : _save, child: const Text('保存音色'))),
      );
}
