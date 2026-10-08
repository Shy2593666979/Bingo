import 'dart:async';
import 'dart:convert';

import 'package:bingo/core/role_avatar_store.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/avatar_crop_page.dart';
import 'package:bingo/features/auth/presentation/voice_record_page.dart';
import 'package:bingo/features/auth/presentation/voice_clone_progress.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/roles/role_traits.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
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
  late final TextEditingController _roleType;
  late String _personality;
  bool get _builtin => widget.role?.builtin ?? false;
  static const _personalities = [
    '温柔体贴',
    '理性严谨',
    '幽默风趣',
    '尖酸刻薄',
    '积极活泼',
    '沉稳克制'
  ];
  RoleOption? _role;
  String? _avatarData;
  String? _voiceId;
  String? _error;
  bool _busy = false;
  bool _playing = false;
  bool _saved = false;
  bool _cloned = false;
  bool _cloning = false;
  bool _expandedTraits = false;
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
    _name = TextEditingController(text: widget.role?.displayName);
    _roleType = TextEditingController(text: widget.role?.typeLabel);
    _personality = widget.role?.personality ?? '温柔体贴';
    _prompt = TextEditingController(text: widget.role?.prompt);
    _avatarData = widget.role?.avatarData;
    _voiceId = widget.role?.voiceSourceId ?? widget.roles.firstOrNull?.id;
    _cloned = widget.role?.hasClonedVoice ?? false;
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
    _roleType.dispose();
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
      prompt: _builtin
          ? (_prompt.text.trim().isEmpty ? '陪伴用户自然交流。' : _prompt.text.trim())
          : _prompt.text.trim(),
      roleType: _roleType.text.trim(),
      personality: _personality,
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
      _cloning = true;
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
        if (!mounted) return;
        setState(() => _progress = switch (status['stage']) {
              'pending' => '录音已收到，等待处理…',
              'uploading' => '正在准备录音下载…',
              'cloning' => '正在复刻声音，请稍等…',
              'verifying' => '正在验证音色是否可用…',
              _ => '正在复刻声音，请稍等…',
            });
        if (status['status'] == 'ready') {
          if (mounted) {
            setState(() {
              _cloned = true;
              _voiceId = role.id;
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
          _cloning = false;
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

  List<RoleOption> get _voiceChoices {
    final choices = widget.roles.where((role) => role.hasVoice).toList();
    if (_cloned && _role != null) {
      choices.removeWhere((role) => role.id == _role!.id);
      choices.add(RoleOption(
          id: _role!.id,
          name: _role!.name,
          nickname: _name.text.trim(),
          avatarData: _avatarData,
          builtin: false,
          hasClonedVoice: true,
          voiceSourceId: _role!.id));
    }
    return choices;
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
    final choices = _voiceChoices;
    final selected =
        choices.any((role) => role.id == _voiceId) ? _voiceId : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            if (selected != null) ...[
                              _voiceAvatar(choices
                                  .firstWhere((role) => role.id == selected)),
                              const SizedBox(width: 9),
                            ],
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
                                        leading: _voiceAvatar(role),
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

  Widget _voiceAvatar(RoleOption role) => role.builtin
      ? AssistantAvatar(role: role.name, size: 26)
      : ClipOval(child: UserAvatar(avatarData: role.avatarData, size: 26));

  Widget _panel(String title, IconData icon, Widget child) => Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: BingoPalette.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: BingoPalette.blue),
          const SizedBox(width: 9),
          Text(title,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
        child: Stack(children: [
          Scaffold(
            backgroundColor: BingoPalette.ice,
            appBar: AppBar(
                centerTitle: true,
                title: Text(widget.role == null ? '创建伙伴' : '编辑伙伴')),
            body: DecoratedBox(
                decoration: const BoxDecoration(
                    gradient: BingoPalette.companionGradient),
                child: SafeArea(
                    child: AbsorbPointer(
                        absorbing: _busy,
                        child: Theme(
                            data: Theme.of(context).copyWith(
                                inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                                    fillColor: const Color(0xFFF7FAF7),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 13),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none),
                                    disabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFB8D8C3))))),
                            child: Form(
                                key: _form,
                                child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), children: [
                                  Row(children: [
                                    InkWell(
                                        onTap: _builtin ? null : _chooseAvatar,
                                        borderRadius: BorderRadius.circular(18),
                                        child: Stack(children: [
                                          _builtin
                                              ? AssistantAvatar(
                                                  role: widget.role!.name,
                                                  size: 64)
                                              : UserAvatar(
                                                  avatarData: _avatarData,
                                                  size: 64),
                                          if (!_builtin)
                                            Positioned(
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                    padding:
                                                        const EdgeInsets.all(5),
                                                    decoration:
                                                        const BoxDecoration(
                                                            color:
                                                                BingoPalette
                                                                    .avatarButton,
                                                            shape: BoxShape
                                                                .circle),
                                                    child: const Icon(
                                                        Icons
                                                            .photo_camera_outlined,
                                                        color: BingoPalette
                                                            .avatarButtonInk,
                                                        size: 15))),
                                        ])),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(
                                              _builtin
                                                  ? '熟悉的 TA，新的默契'
                                                  : '让陪伴，有自己的样子',
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 7),
                                          const Text('一个名字，一种性格，一个熟悉的声音。',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF7D918A))),
                                        ])),
                                  ]),
                                  const SizedBox(height: 22),
                                  if (_builtin)
                                    const Padding(
                                        padding: EdgeInsets.only(bottom: 14),
                                        child: Text('系统伙伴的身份保持不变，聊天性格可以自由调整。',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF7D918A)))),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          border: Border.all(
                                              color: BingoPalette.line)),
                                      child: Column(children: [
                                        _panel(
                                            '伙伴昵称',
                                            Icons.person_outline_rounded,
                                            TextFormField(
                                                controller: _name,
                                                enabled: !_builtin,
                                                maxLength: 30,
                                                decoration:
                                                    const InputDecoration(
                                                        counterText: '',
                                                        hintText:
                                                            '给 TA 起一个亲切的名字'),
                                                validator: (value) =>
                                                    (value?.trim().isEmpty ??
                                                            true)
                                                        ? '请输入伙伴昵称'
                                                        : null)),
                                        _panel(
                                            '伙伴角色',
                                            Icons.badge_outlined,
                                            TextFormField(
                                                controller: _roleType,
                                                enabled: !_builtin,
                                                maxLength: 30,
                                                decoration:
                                                    const InputDecoration(
                                                        hintText:
                                                            '你希望 TA 以怎样的身份陪伴你',
                                                        counterText: ''))),
                                        _panel(
                                            '伙伴性格',
                                            Icons.favorite_border_rounded,
                                            Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Wrap(
                                                      spacing: 7,
                                                      runSpacing: 8,
                                                      children: [
                                                        for (final personality
                                                            in _personalities)
                                                          ChoiceChip(
                                                              label: Text(
                                                                  personality,
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          12)),
                                                              selected: _personality ==
                                                                  personality,
                                                              showCheckmark:
                                                                  false,
                                                              side: BorderSide(
                                                                  color: _personality == personality
                                                                      ? const Color(
                                                                          0xFFC0DFCC)
                                                                      : const Color(
                                                                          0xFFE7EEE8)),
                                                              shape: RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                          11)),
                                                              materialTapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                              selectedColor:
                                                                  const Color(
                                                                      0xFFE5F4E9),
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFFF7FAF7),
                                                              onSelected: (_) =>
                                                                  setState(() => _personality = personality)),
                                                      ]),
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                      '只影响这位伙伴，其他伙伴保持不变。',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: Color(
                                                              0xFF7D918A))),
                                                ])),
                                        if (!_builtin) ...[
                                          _panel(
                                              '伙伴设定',
                                              Icons.note_alt_outlined,
                                              Column(children: [
                                                TextFormField(
                                                    controller: _prompt,
                                                    minLines: 3,
                                                    maxLines: 7,
                                                    maxLength: 2000,
                                                    decoration:
                                                        const InputDecoration(
                                                            counterText: '',
                                                            hintText:
                                                                'TA 是谁？怎样说话？你希望 TA 怎样陪伴你？'),
                                                    validator: (value) => (value
                                                                ?.trim()
                                                                .isEmpty ??
                                                            true)
                                                        ? '请描述这个伙伴'
                                                        : null),
                                                Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: TextButton(
                                                        onPressed: () {
                                                          _prompt.text =
                                                              '你是一位温柔、有耐心的陪伴伙伴。认真倾听我的心情，用自然亲切的语言交流，给予理解和鼓励。';
                                                        },
                                                        child: const Text(
                                                            '试试这个设定'))),
                                              ])),
                                          _panel(
                                              '陪伴特征',
                                              Icons.auto_awesome_outlined,
                                              _traitPicker()),
                                          _panel(
                                              '伙伴声音',
                                              Icons.graphic_eq_rounded,
                                              _voicePicker(voiceLabel)),
                                        ],
                                      ])),
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
                                ])))))),
            bottomNavigationBar: SafeArea(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                    child: SizedBox(
                        height: 54,
                        child: FilledButton(
                            onPressed: _busy ? null : _save,
                            style: companionActionButtonStyle(),
                            child: Text(widget.role == null ? '创建伙伴' : '保存修改',
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)))))),
          ),
          if (_cloning)
            Positioned.fill(child: VoiceCloneProgress(message: _progress)),
        ]));
  }
}
