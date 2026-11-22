import 'package:bingo/core/design/bingo_page.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'dart:async';
import 'package:bingo/core/design/companion_launch_ui.dart';
import 'package:bingo/core/widgets/bingo_confirm_dialog.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/reply_audio_player.dart';
import 'package:bingo/features/voices/data/voice_gateway.dart';
import 'package:bingo/features/voices/models/voice_option.dart';
import 'package:bingo/features/voices/presentation/voice_cover.dart';
import 'package:bingo/features/voices/presentation/voice_editor_page.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VoiceLibraryPage extends StatefulWidget {
  const VoiceLibraryPage(
      {required this.gateway,
      this.roles,
      this.picking = false,
      this.selectedId,
      this.onChanged,
      super.key});
  final VoiceGateway gateway;
  final RoleGateway? roles;
  final bool picking;
  final String? selectedId;
  final Future<void> Function()? onChanged;
  @override
  State<VoiceLibraryPage> createState() => _VoiceLibraryPageState();
}

class _VoiceLibraryPageState extends State<VoiceLibraryPage>
    with WidgetsBindingObserver {
  static const _device = MethodChannel('bingo/device_tools');
  final _streamAudio = ReplyAudioPlayer(channelSuffix: 'PreviewStreamAudio');
  List<VoiceOption>? _voices;
  String? _selected, _playing, _error, _gender;
  int _tab = 0, _generation = 0;
  bool _applying = false;
  Timer? _refresh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selected = widget.selectedId;
    _load(initial: true);
  }

  Future<void> _stop() async {
    final gateway = widget.gateway;
    if (gateway is StreamingVoiceGateway) {
      (gateway as StreamingVoiceGateway).stopVoicePreview();
    }
    await Future.wait([
      _streamAudio.stop(),
      _device.invokeMethod<void>('stopPreviewAudio').catchError((_) {}),
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _generation++;
      if (_playing != null) setState(() => _playing = null);
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    _generation++;
    _refresh?.cancel();
    unawaited(_stop());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final voices = await widget.gateway.listVoices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _error = null;
        final chosen =
            voices.where((voice) => voice.id == _selected).firstOrNull;
        if (initial && chosen != null) _tab = _scopeIndex(chosen.scope);
        if (chosen == null) _selected = null;
      });
      _refresh?.cancel();
      if (voices.any((voice) => voice.status == 'processing')) {
        _refresh = Timer(const Duration(seconds: 4), _load);
      }
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = error is ApiException ? error.message : '音色库加载失败，请重试');
      }
    }
  }

  int _scopeIndex(String scope) => scope == 'system'
      ? 1
      : scope == 'community'
          ? 2
          : 0;
  List<VoiceOption> get _visible => (_voices ?? [])
      .where((voice) =>
          _scopeIndex(voice.scope) == _tab &&
          (_gender == null || voice.gender == _gender))
      .toList();
  VoiceOption? get _chosen =>
      (_voices ?? []).where((voice) => voice.id == _selected).firstOrNull;
  Future<void> _preview(VoiceOption voice) async {
    final generation = ++_generation;
    final stop = _playing == voice.id;
    setState(() {
      _playing = stop ? null : voice.id;
      _error = null;
    });
    try {
      await _stop();
      if (stop || !mounted || generation != _generation) return;
      final gateway = widget.gateway;
      if (gateway is StreamingVoiceGateway) {
        try {
          await for (final chunk in (gateway as StreamingVoiceGateway)
              .streamVoicePreview(voice.id)) {
            if (!mounted || generation != _generation) return;
            await _streamAudio.add(chunk);
          }
          if (mounted && generation == _generation) await _streamAudio.finish();
          return;
        } on ApiException catch (error) {
          if (error.statusCode != 404) rethrow;
        }
      }
      if (!mounted || generation != _generation) return;
      final audio = await widget.gateway.previewVoice(voice.id);
      if (!mounted || generation != _generation) return;
      await _device.invokeMethod<void>('playPreviewAudio', audio);
    } catch (error) {
      if (mounted && generation == _generation) {
        unawaited(_streamAudio.stop());
        setState(
            () => _error = error is ApiException ? error.message : '试听失败，请重试');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _playing = null);
    }
  }

  Future<void> _edit([VoiceOption? voice]) async {
    _generation++;
    if (_playing != null) setState(() => _playing = null);
    await _stop();
    if (!mounted) return;
    final result = await Navigator.of(context).push<VoiceOption>(
        MaterialPageRoute(
            builder: (_) =>
                VoiceEditorPage(gateway: widget.gateway, voice: voice)));
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _selected = result.id;
        _tab = 0;
        _gender = null;
      });
    }
    await _load();
  }

  Future<void> _delete(VoiceOption voice) async {
    final confirmed = await showBingoConfirmDialog(context,
        title: '删除这个音色？',
        message: '音色删除后无法恢复，正在使用的音色需要先为搭子更换。',
        confirmLabel: '删除音色',
        destructive: true,
        icon: Icons.graphic_eq_rounded);
    if (confirmed != true || !mounted) return;
    try {
      _generation++;
      if (_playing != null) setState(() => _playing = null);
      await _stop();
      await widget.gateway.deleteVoice(voice.id);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error is ApiException ? error.message : '删除失败，请重试');
      }
    }
  }

  Future<void> _apply() async {
    final voice = _chosen;
    if (voice == null || !voice.ready || _applying) return;
    _generation++;
    await _stop();
    if (!mounted) return;
    if (widget.picking) {
      Navigator.pop(context, voice);
      return;
    }
    final roles = widget.roles;
    if (roles == null) return;
    setState(() => _applying = true);
    try {
      final choices = await roles.listRoles();
      if (!mounted) return;
      if (choices.isEmpty) {
        showCenterToast(context, '先创建或添加一位搭子吧');
        return;
      }
      final roleId = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          backgroundColor: Colors.white,
          isScrollControlled: true,
          builder: (sheet) => SafeArea(
              child: SizedBox(
                  height: MediaQuery.sizeOf(sheet).height * .6,
                  child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('给哪位搭子使用？',
                            style: CompanionLaunch.text(18,
                                weight: FontWeight.w500))),
                    Expanded(
                        child: ListView(children: [
                      for (final role in choices)
                        ListTile(
                            leading: AssistantAvatar(role: role.name, size: 42),
                            title: Text(role.displayName),
                            subtitle: Text(role.voiceName ?? '尚未选择音色'),
                            trailing: role.voiceId == voice.id
                                ? const Icon(Icons.check_rounded)
                                : null,
                            onTap: () => Navigator.pop(sheet, role.id)),
                    ])),
                  ]))));
      if (roleId == null || !mounted) return;
      await widget.gateway.assignRoleVoice(roleId, voice.id);
      await widget.onChanged?.call();
      if (mounted) showCenterToast(context, '音色已应用');
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error is ApiException ? error.message : '设置失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Widget _tile(VoiceOption voice) => Padding(
      key: ValueKey('voice-asset-${voice.id}'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
          color: BingoPalette.voiceSurface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: voice.ready
                  ? () => setState(() => _selected = voice.id)
                  : voice.editable
                      ? () => _edit(voice)
                      : null,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Semantics(
                        label: '试听${voice.name}',
                        button: true,
                        child: GestureDetector(
                            onTap:
                                voice.hasAudio ? () => _preview(voice) : null,
                            child: VoiceCover(
                                id: voice.id,
                                showPlay: voice.hasAudio,
                                playing: _playing == voice.id))),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(voice.name,
                              style: CompanionLaunch.text(16,
                                  weight: FontWeight.w600)),
                          const SizedBox(height: 7),
                          Text(voice.statusLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: CompanionLaunch.text(13,
                                  color: const Color(0xFF666666))),
                        ])),
                    const SizedBox(width: 10),
                    Icon(
                        _selected == voice.id
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: _selected == voice.id
                            ? CompanionLaunch.primary
                            : const Color(0xFFAAAAAA),
                        size: 22),
                    if (voice.editable)
                      PopupMenuButton<String>(
                          tooltip: '管理${voice.name}',
                          onSelected: (action) =>
                              action == 'edit' ? _edit(voice) : _delete(voice),
                          itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'edit', child: Text('编辑音色')),
                                const PopupMenuItem(
                                    value: 'delete', child: Text('删除音色'))
                              ]),
                  ])))));
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
            title: Text(widget.picking ? '选择音色' : '我的音色'), centerTitle: true),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Container(
                      margin: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                      constraints: const BoxConstraints(minHeight: 84),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                          color: BingoPalette.blush,
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        const Icon(Icons.graphic_eq_rounded,
                            size: 26, color: BingoPalette.primary),
                        const SizedBox(width: 16),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  '我的音色 ${(_voices ?? []).where((v) => v.scope == 'private').length} 个',
                                  style: CompanionLaunch.text(15,
                                      weight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text('为搭子添加专属声音',
                                  style: CompanionLaunch.text(14,
                                      color: const Color(0xFF666666))),
                            ])),
                        const SizedBox(width: 6),
                        TextButton(
                            onPressed: _edit,
                            child: const Text('录制',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600))),
                      ])),
                  CompanionLaunchTabs(
                      tabs: [
                        (value: 0, label: '我的音色'),
                        (value: 1, label: '系统音色'),
                        (value: 2, label: '社区音色'),
                      ],
                      selected: _tab,
                      onSelected: (tab) => setState(() {
                            _tab = tab;
                            _gender = null;
                          })),
                  if (_tab == 0)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                        child: OutlinedButton.icon(
                            key: const ValueKey('create-voice'),
                            onPressed: _edit,
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                                side:
                                    const BorderSide(color: Color(0xFFF0F0F0)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20))),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('创建新音色',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)))),
                  if (_tab != 0)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final item in [
                            (null, '全部'),
                            ('male', '男声'),
                            ('female', '女声')
                          ])
                            ChoiceChip(
                                label: Text(item.$2),
                                backgroundColor: BingoPalette.softSurface,
                                selectedColor: const Color(0xFFF7ECE7),
                                labelStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: BingoPalette.ink),
                                side: const BorderSide(
                                    color: BingoPalette.accentBorder),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                selected: _gender == item.$1,
                                onSelected: (_) =>
                                    setState(() => _gender = item.$1)),
                        ])),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                          TextButton(
                              onPressed: _load, child: const Text('重新加载'))
                        ])),
                  if (_voices == null && _error == null)
                    const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator())),
                  if (_voices != null && _visible.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(_tab == 0 ? '创建一个属于自己的声音吧。' : '暂无符合条件的音色。',
                            style: CompanionLaunch.text(14,
                                color: CompanionLaunch.muted))),
                  for (final voice in _visible) _tile(voice),
                ])),
        bottomNavigationBar: BingoActionBar(
            child: Row(children: [
          Expanded(
              child: Text(_chosen?.name ?? '选择一个喜欢的声音',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CompanionLaunch.text(14,
                      color: const Color(0xFF737373)))),
          const SizedBox(width: 12),
          FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(116, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  disabledBackgroundColor: const Color(0xFFE5E5E5),
                  disabledForegroundColor: const Color(0xFF999999),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              onPressed: _chosen?.ready == true && !_applying ? _apply : null,
              child: Text(_applying
                  ? '正在设置…'
                  : widget.picking
                      ? '使用此音色'
                      : '给搭子使用')),
        ])),
      );
}
