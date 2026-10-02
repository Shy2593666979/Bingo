import 'dart:async';
import 'dart:convert';

import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/avatar_crop_page.dart';
import 'package:bingo/features/auth/presentation/voice_record_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/roles/role_traits.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RoleEditorPage extends StatefulWidget {
  const RoleEditorPage(
      {required this.gateway, required this.roles, this.role, super.key});
  final RoleGateway gateway;
  final List<RoleOption> roles;
  final RoleOption? role;

  @override
  State<RoleEditorPage> createState() => _RoleEditorPageState();
}

class _RoleEditorPageState extends State<RoleEditorPage>
    with WidgetsBindingObserver {
  static const _device = MethodChannel('bingo/device_tools');
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  RoleOption? _role;
  String? _avatarData;
  String? _voiceId;
  String? _error;
  bool _busy = false;
  bool _playing = false;
  bool _saved = false;
  bool _cloned = false;
  bool _expandedTraits = false;
  bool _systemVoice = true;
  bool _voiceExpanded = false;
  final _voiceOptionsKey = GlobalKey();
  String _progress = '';
  late List<String> _traits;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _role = widget.role;
    _traits = List.of(widget.role?.traits ?? ['善于倾听', '陪伴聊天']);
    _name = TextEditingController(text: widget.role?.name);
    _prompt = TextEditingController(text: widget.role?.prompt);
    _avatarData = widget.role?.avatarData;
    _voiceId = widget.role?.voiceSourceId ?? widget.roles.firstOrNull?.id;
    _cloned = widget.role?.hasClonedVoice ?? false;
    _systemVoice = !_cloned &&
        (widget.roles
                .where((role) => role.id == _voiceId)
                .firstOrNull
                ?.builtin ??
            true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_device.invokeMethod<void>('stopPreviewAudio'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_device.invokeMethod<void>('stopPreviewAudio'));
    if (!_saved && widget.role == null && _role != null) {
      unawaited(widget.gateway.deleteRole(_role!.id).catchError((Object _) {}));
      RoleAvatarStore.set(_role!.name, null);
    }
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _chooseAvatar() async {
    try {
      final picked =
          await _device.invokeMapMethod<String, dynamic>('pickImage');
      if (!mounted || picked == null) return;
      final image = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(
              builder: (_) =>
                  AvatarCropPage(image: picked['bytes'] as Uint8List)));
      if (image != null && mounted) {
        setState(() => _avatarData = base64Encode(image));
      }
    } on PlatformException catch (error) {
      if (mounted) showCenterToast(context, error.message ?? '无法打开相册，请重试');
    }
  }

  Future<RoleOption> _persist({required bool draft}) async {
    final result = await widget.gateway.saveRole(
      id: _role?.id,
      name: _name.text.trim(),
      prompt: _prompt.text.trim(),
      avatarData: _avatarData,
      voiceSourceId: _voiceId,
      draft: draft,
      traits: _traits,
    );
    _role = result;
    return result;
  }

  Future<void> _record() async {
    if (!_form.currentState!.validate()) return;
    await _device.invokeMethod<void>('stopPreviewAudio');
    if (!mounted) return;
    final audio = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => const VoiceRecordPage()));
    if (audio == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = '正在上传录音…';
    });
    try {
      final role = await _persist(draft: widget.role == null);
      final job = await widget.gateway.cloneRoleVoice(role.id, audio);
      if (mounted) setState(() => _progress = '正在复刻声音，请稍等…');
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(deadline)) {
        final status = await widget.gateway.voiceJob(job);
        if (status['status'] == 'ready') {
          if (mounted) {
            setState(() {
              _cloned = true;
              _voiceId = role.id;
              _systemVoice = false;
            });
            showCenterToast(context, '声音复刻成功，点击试听听听效果');
          }
          return;
        }
        if (status['status'] == 'failed') {
          throw ApiException(status['error'] as String? ?? '复刻失败，请重新录制');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      throw const ApiException('复刻仍在处理中，请稍后重试');
    } on Exception catch (error) {
      if (mounted) {
        setState(() =>
            _error = error is ApiException ? error.message : '声音复刻失败，请检查网络后重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _preview() async {
    if (_playing) {
      await _device.invokeMethod<void>('stopPreviewAudio');
      return;
    }
    final voiceId = _voiceId;
    if (voiceId == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = '正在生成中文试听…';
    });
    try {
      final audio = await widget.gateway.previewRoleVoice(voiceId);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _playing = true;
        _progress = '';
      });
      await _device.invokeMethod<void>('playPreviewAudio', audio);
    } on Exception catch (error) {
      if (mounted) {
        setState(() =>
            _error = error is ApiException ? error.message : '试听失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _playing = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_traits.length < 2 || _traits.length > 3) {
      showCenterToast(context, '请选择 2～3 个陪伴特征');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = '正在保存伙伴…';
    });
    try {
      await _device.invokeMethod<void>('stopPreviewAudio');
      final role = await _persist(draft: false);
      _saved = true;
      if (mounted) Navigator.of(context).pop(role);
    } on Exception catch (error) {
      if (mounted) {
        setState(() =>
            _error = error is ApiException ? error.message : '保存失败，请检查网络后重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _delete() async {
    final affected = widget.roles
        .where(
            (role) => role.id != _role!.id && role.voiceSourceId == _role!.id)
        .length;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('删除这个伙伴？'),
              content: Text('删除后，这个伙伴创建的复刻音色也会失效。'
                  '${affected > 0 ? '\n另外 $affected 个伙伴正在使用它的音色，将自动切回系统默认音色。' : ''}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _progress = '正在删除伙伴…';
    });
    try {
      await widget.gateway.deleteRole(_role!.id);
      RoleAvatarStore.set(_role!.name, null);
      _saved = true;
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (error) {
      if (mounted) {
        setState(
            () => _error = error is ApiException ? error.message : '删除失败，请重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  List<RoleOption> get _voiceChoices {
    final choices = widget.roles.where((role) => role.hasVoice).toList();
    if (_cloned && _role != null) {
      choices.removeWhere((role) => role.id == _role!.id);
      choices.add(RoleOption(
          id: _role!.id,
          name: '我的复刻声音',
          builtin: false,
          hasClonedVoice: true,
          voiceSourceId: _role!.id));
    }
    return choices;
  }

  Future<void> _switchVoice(bool system) async {
    await _device.invokeMethod<void>('stopPreviewAudio');
    if (!mounted) return;
    final choices =
        _voiceChoices.where((role) => role.builtin == system).toList();
    setState(() {
      _systemVoice = system;
      _voiceExpanded = false;
      if (choices.isNotEmpty && !choices.any((role) => role.id == _voiceId)) {
        _voiceId = choices.first.id;
      }
    });
  }

  Widget _traitPicker() {
    final options = roleTraits.keys.toList();
    final visible = _expandedTraits
        ? options
        : options
            .where((label) =>
                options.indexOf(label) < 8 || _traits.contains(label))
            .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
            child: Text('选择 2～3 个特征',
                style: TextStyle(fontSize: 12, color: Color(0xFF7D918A)))),
        Text('已选 ${_traits.length} / 3',
            style: const TextStyle(fontSize: 11, color: Color(0xFF7D918A))),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 7, runSpacing: 8, children: [
        for (final label in visible)
          Semantics(
              button: true,
              selected: _traits.contains(label),
              child: Material(
                  color: _traits.contains(label)
                      ? const Color(0xFFE7F4EC)
                      : const Color(0xFFF9FCFA),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: _traits.contains(label)
                              ? const Color(0xFF9FCDB8)
                              : BingoPalette.line)),
                  child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        if (!_traits.contains(label) && _traits.length >= 3) {
                          showCenterToast(context, '最多选择 3 个伙伴特征');
                          return;
                        }
                        setState(() {
                          if (_traits.contains(label)) {
                            _traits.remove(label);
                          } else {
                            _traits.add(label);
                          }
                        });
                      },
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            TraitIcon(roleTraits[label]!, size: 14),
                            const SizedBox(width: 4),
                            Text(label,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF527464))),
                          ]))))),
      ]),
      TextButton(
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          onPressed: () => setState(() => _expandedTraits = !_expandedTraits),
          child: Text(_expandedTraits ? '收起更多特征' : '展开更多特征',
              style: const TextStyle(fontSize: 12))),
    ]);
  }

  Widget _voicePicker(String voiceLabel) {
    final choices =
        _voiceChoices.where((role) => role.builtin == _systemVoice).toList();
    final selected =
        choices.any((role) => role.id == _voiceId) ? _voiceId : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: const Color(0xFFF0F7F2),
              borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            for (final system in [true, false])
              Expanded(
                  child: TextButton(
                      onPressed: () => _switchVoice(system),
                      style: TextButton.styleFrom(
                          backgroundColor: _systemVoice == system
                              ? Colors.white
                              : Colors.transparent,
                          foregroundColor: _systemVoice == system
                              ? BingoPalette.blue
                              : const Color(0xFF7D918A),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11))),
                      child: Text(system ? '系统音色' : '已有伙伴',
                          style: const TextStyle(fontSize: 12)))),
          ])),
      const SizedBox(height: 12),
      if (choices.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('暂无可用的伙伴音色，可以通过录音创建。',
                style: TextStyle(fontSize: 12, color: Color(0xFF7D918A))))
      else
        TapRegion(
            onTapOutside: (_) {
              if (_voiceExpanded) setState(() => _voiceExpanded = false);
            },
            child: Column(children: [
              Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: BingoPalette.line)),
                  child: InkWell(
                      key: const ValueKey('voice-selector'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() => _voiceExpanded = !_voiceExpanded);
                        if (_voiceExpanded) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final optionsContext =
                                _voiceOptionsKey.currentContext;
                            if (mounted && optionsContext != null) {
                              Scrollable.ensureVisible(optionsContext,
                                  alignmentPolicy: ScrollPositionAlignmentPolicy
                                      .keepVisibleAtEnd,
                                  duration: const Duration(milliseconds: 180));
                            }
                          });
                        }
                      },
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                                    choices
                                            .where(
                                                (role) => role.id == selected)
                                            .firstOrNull
                                            ?.displayName ??
                                        '请选择音色',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13))),
                            Icon(
                                _voiceExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 22,
                                color: const Color(0xFF7D918A)),
                          ])))),
              if (_voiceExpanded) ...[
                const SizedBox(height: 6),
                Material(
                    key: _voiceOptionsKey,
                    color: Colors.white,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: BingoPalette.line)),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 216),
                        child: SingleChildScrollView(
                            key: const ValueKey('voice-options'),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final role in choices)
                                    ListTile(
                                        key:
                                            ValueKey('voice-option-${role.id}'),
                                        dense: true,
                                        selected: role.id == selected,
                                        selectedTileColor:
                                            const Color(0xFFEFF7F2),
                                        title: Text(role.displayName,
                                            style:
                                                const TextStyle(fontSize: 13)),
                                        trailing: role.id == selected
                                            ? const Icon(Icons.check_rounded,
                                                size: 18,
                                                color: BingoPalette.blue)
                                            : null,
                                        onTap: () async {
                                          await _device.invokeMethod<void>(
                                              'stopPreviewAudio');
                                          if (mounted) {
                                            setState(() {
                                              _voiceId = role.id;
                                              _voiceExpanded = false;
                                            });
                                          }
                                        }),
                                ])))),
              ],
            ])),
      Row(children: [
        Expanded(
            child: Text('当前音色：$voiceLabel',
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFF7D918A)))),
        TextButton.icon(
            onPressed: _voiceId == null ? null : _preview,
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow_rounded,
                size: 16),
            label: Text(_playing ? '停止试听' : '中文试听',
                style: const TextStyle(fontSize: 11))),
      ]),
      const SizedBox(height: 4),
      Material(
          color: const Color(0xFFF5FAF7),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFC9E4D6))),
          child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _record,
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const Icon(Icons.mic_none_rounded,
                        size: 23, color: Color(0xFF5E9B7D)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(_cloned ? '重新录音，复刻声音' : '录一段声音，让 TA 更熟悉',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          const Text('按引导朗读 20～30 秒，无需手动上传音频',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFF7D918A))),
                        ])),
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: Color(0xFF7D918A)),
                  ])))),
      const SizedBox(height: 10),
      const Text('少于 15 秒需要重新录制，复刻完成后可试听。',
          style: TextStyle(fontSize: 11, color: Color(0xFF7D918A))),
    ]);
  }

  Widget _panel(String title, IconData icon, Widget child) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: BingoPalette.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: BingoPalette.blue),
          const SizedBox(width: 9),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        child,
      ]));

  @override
  Widget build(BuildContext context) {
    final voices = widget.roles.where((role) => role.id == _voiceId);
    final voiceLabel = _cloned && _voiceId == _role?.id
        ? '我的复刻声音'
        : (voices.firstOrNull?.displayName ?? '系统默认');
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: BingoPalette.ice,
          appBar: AppBar(
              centerTitle: true,
              title: Text(widget.role == null ? '创建伙伴' : '编辑伙伴')),
          body: DecoratedBox(
              decoration:
                  const BoxDecoration(gradient: BingoPalette.softGradient),
              child: SafeArea(
                  child: AbsorbPointer(
                      absorbing: _busy,
                      child: Form(
                          key: _form,
                          child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 12, 20, 20),
                              children: [
                                Center(
                                    child: InkWell(
                                        onTap: _chooseAvatar,
                                        borderRadius: BorderRadius.circular(50),
                                        child: Stack(children: [
                                          ClipOval(
                                              child: _avatarData == null
                                                  ? Image.asset(
                                                      'assets/images/bingo_logo.png',
                                                      width: 88,
                                                      height: 88)
                                                  : Image.memory(
                                                      base64Decode(
                                                          _avatarData!),
                                                      width: 88,
                                                      height: 88,
                                                      fit: BoxFit.cover)),
                                          Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                  padding:
                                                      const EdgeInsets.all(7),
                                                  decoration:
                                                      const BoxDecoration(
                                                          color:
                                                              BingoPalette
                                                                  .avatarButton,
                                                          shape:
                                                              BoxShape.circle),
                                                  child: const Icon(
                                                      Icons
                                                          .photo_camera_outlined,
                                                      color: BingoPalette
                                                          .avatarButtonInk,
                                                      size: 17))),
                                        ]))),
                                Center(
                                    child: TextButton(
                                        onPressed: _chooseAvatar,
                                        style: TextButton.styleFrom(
                                            foregroundColor:
                                                BingoPalette.avatarButtonInk),
                                        child: const Text('更换头像'))),
                                const Center(
                                    child: Text('让陪伴，有自己的样子',
                                        style: TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w700))),
                                const SizedBox(height: 6),
                                const Text('一个名字，一份默契，一个熟悉的声音。',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF7D918A))),
                                const SizedBox(height: 22),
                                _panel(
                                    '伙伴昵称',
                                    Icons.person_outline_rounded,
                                    TextFormField(
                                        controller: _name,
                                        maxLength: 30,
                                        decoration: const InputDecoration(
                                            hintText: '给 TA 起一个亲切的名字'),
                                        validator: (value) =>
                                            (value?.trim().isEmpty ?? true)
                                                ? '请输入伙伴昵称'
                                                : null)),
                                _panel(
                                    '伙伴设定',
                                    Icons.edit_note_rounded,
                                    Column(children: [
                                      TextFormField(
                                          controller: _prompt,
                                          minLines: 3,
                                          maxLines: 7,
                                          maxLength: 2000,
                                          decoration: const InputDecoration(
                                              hintText:
                                                  'TA 是谁？怎样说话？你希望 TA 怎样陪伴你？'),
                                          validator: (value) =>
                                              (value?.trim().isEmpty ?? true)
                                                  ? '请描述这个伙伴'
                                                  : null),
                                      Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                              onPressed: () {
                                                _prompt.text =
                                                    '你是一位温柔、有耐心的陪伴伙伴。认真倾听我的心情，用自然亲切的语言交流，给予理解和鼓励。';
                                              },
                                              child: const Text('试试这个设定'))),
                                    ])),
                                _panel('陪伴特征', Icons.auto_awesome_outlined,
                                    _traitPicker()),
                                _panel('伙伴声音', Icons.graphic_eq_rounded,
                                    _voicePicker(voiceLabel)),
                                if (_busy)
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const SizedBox.square(
                                                dimension: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2)),
                                            const SizedBox(width: 12),
                                            Flexible(child: Text(_progress)),
                                          ])),
                                if (_error != null)
                                  Text(_error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)),
                                if (widget.role != null)
                                  TextButton(
                                      onPressed: _delete,
                                      child: Text('删除伙伴',
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error))),
                              ]))))),
          bottomNavigationBar: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: SizedBox(
                      height: 54,
                      child: FilledButton(
                          onPressed: _busy ? null : _save,
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF129A81),
                              shape: const StadiumBorder()),
                          child: Text(widget.role == null ? '创建伙伴' : '保存修改',
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)))))),
        ));
  }
}
