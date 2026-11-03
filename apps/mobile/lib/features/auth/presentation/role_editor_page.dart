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
  late final TextEditingController _description, _opening;
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
    _description = TextEditingController(text: widget.role?.description);
    _opening = TextEditingController(text: widget.role?.openingLine);
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
    _description.dispose();
    _opening.dispose();
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
      description: _description.text.trim(),
      openingLine: _opening.text.trim(),
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
      _progress = '正在保存搭子…';
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
                style: TextStyle(fontSize: 12, color: Color(0xFF738297)))),
        Text('已选 ${_traits.length} / 3',
            style: const TextStyle(fontSize: 11, color: Color(0xFF738297))),
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
                          showCenterToast(context, '最多选择 3 个搭子特征');
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
            child: Text('暂无可用的搭子音色，可以通过录音创建。',
                style: TextStyle(fontSize: 12, color: Color(0xFF738297))))
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
                                color: const Color(0xFF738297)),
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
                    const TextStyle(fontSize: 11, color: Color(0xFF738297)))),
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
                                  fontSize: 10, color: Color(0xFF738297))),
                        ])),
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: Color(0xFF738297)),
                  ])))),
      const SizedBox(height: 10),
      const Text('少于 15 秒需要重新录制，复刻完成后可试听。',
          style: TextStyle(fontSize: 11, color: Color(0xFF738297))),
    ]);
  }

  Widget _voiceAvatar(RoleOption role) =>
      role.builtin || (role.avatarData?.isEmpty ?? true)
          ? AssistantAvatar(role: role.name, size: 26)
          : UserAvatar(avatarData: role.avatarData, size: 26);

  Widget _label(String title) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 9),
      child: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)));
  @override
  Widget build(BuildContext context) {
    final voiceLabel = _cloned && _voiceId == _role?.id
        ? '我的复刻声音'
        : widget.roles
                .where((role) => role.id == _voiceId)
                .firstOrNull
                ?.displayName ??
            '系统默认';
    return PopScope(
        canPop: !_busy,
        child: Stack(children: [
          Scaffold(
              backgroundColor: BingoPalette.pageTop,
              appBar: AppBar(
                  centerTitle: true,
                  title: Text(widget.role == null ? '创建搭子' : '编辑搭子')),
              body: SafeArea(
                  top: false,
                  child: AbsorbPointer(
                      absorbing: _busy,
                      child: Form(
                          key: _form,
                          child: ListView(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              children: [
                                Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    InkWell(
                                                        onTap: _builtin
                                                            ? null
                                                            : _chooseAvatar,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(16),
                                                        child: SizedBox(
                                                            width: 80,
                                                            height: 80,
                                                            child: Stack(
                                                                children: [
                                                                  if (_builtin)
                                                                    AssistantAvatar(
                                                                        role: widget
                                                                            .role!
                                                                            .name,
                                                                        size:
                                                                            80)
                                                                  else if (_avatarData !=
                                                                      null)
                                                                    UserAvatar(
                                                                        avatarData:
                                                                            _avatarData,
                                                                        size:
                                                                            80)
                                                                  else
                                                                    Container(
                                                                        width:
                                                                            80,
                                                                        height:
                                                                            80,
                                                                        decoration: BoxDecoration(
                                                                            color:
                                                                                BingoPalette.softSurface,
                                                                            border: Border.all(color: BingoPalette.primary.withValues(alpha: .4)),
                                                                            borderRadius: BorderRadius.circular(16)),
                                                                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                                          Icon(
                                                                              Icons.add_rounded,
                                                                              size: 29,
                                                                              color: BingoPalette.primary),
                                                                          SizedBox(
                                                                              height: 4),
                                                                          Text(
                                                                              '上传头像',
                                                                              style: TextStyle(fontSize: 10, color: BingoPalette.primary))
                                                                        ])),
                                                                  if (_avatarData !=
                                                                          null &&
                                                                      !_builtin)
                                                                    const Positioned(
                                                                        right:
                                                                            2,
                                                                        bottom:
                                                                            2,
                                                                        child: Icon(
                                                                            Icons
                                                                                .photo_camera_outlined,
                                                                            size:
                                                                                18,
                                                                            color:
                                                                                BingoPalette.primary))
                                                                ]))),
                                                    const SizedBox(width: 14),
                                                    Expanded(
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                          const Text('名称',
                                                              style: TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800)),
                                                          const SizedBox(
                                                              height: 10),
                                                          TextFormField(
                                                              controller: _name,
                                                              enabled:
                                                                  !_builtin,
                                                              maxLength: 30,
                                                              decoration: const InputDecoration(
                                                                  hintText:
                                                                      '给 TA 起一个亲切的名字',
                                                                  counterText:
                                                                      '',
                                                                  contentPadding:
                                                                      EdgeInsets
                                                                          .all(
                                                                              12)),
                                                              validator: (v) =>
                                                                  (v?.trim().isEmpty ??
                                                                          true)
                                                                      ? '请输入搭子昵称'
                                                                      : null)
                                                        ]))
                                                  ]),
                                              if (_builtin) ...[
                                                const SizedBox(height: 16),
                                                const Text(
                                                    '系统搭子的身份保持不变，聊天性格可以自由调整。',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            BingoPalette.muted))
                                              ] else ...[
                                                _label('一句话介绍'),
                                                TextFormField(
                                                    controller: _description,
                                                    maxLength: 200,
                                                    decoration:
                                                        const InputDecoration(
                                                            hintText:
                                                                '用一句话描述你的搭子',
                                                            counterText: '')),
                                                _label('性格与设定'),
                                                TextFormField(
                                                    controller: _prompt,
                                                    minLines: 4,
                                                    maxLines: 7,
                                                    maxLength: 2000,
                                                    decoration:
                                                        const InputDecoration(
                                                            counterText: '',
                                                            hintText:
                                                                'TA 是谁？怎样说话？你希望 TA 怎样陪伴你？'),
                                                    validator: (v) =>
                                                        (v?.trim().isEmpty ??
                                                                true)
                                                            ? '请描述这个搭子'
                                                            : null),
                                                _label('开场白'),
                                                TextFormField(
                                                    controller: _opening,
                                                    minLines: 2,
                                                    maxLines: 3,
                                                    maxLength: 300,
                                                    decoration:
                                                        const InputDecoration(
                                                            hintText:
                                                                '第一次见面，TA 会怎样打招呼？',
                                                            counterText: '')),
                                                _label('声音'),
                                                _voicePicker(voiceLabel),
                                                _label('角色分类'),
                                                Wrap(
                                                    spacing: 7,
                                                    runSpacing: 6,
                                                    children: [
                                                      for (final (label, type, icon)
                                                          in [
                                                        (
                                                          '女友系',
                                                          '女朋友',
                                                          Icons.favorite_rounded
                                                        ),
                                                        (
                                                          '男友系',
                                                          '男朋友',
                                                          Icons.person_rounded
                                                        ),
                                                        (
                                                          '老师系',
                                                          '老师',
                                                          Icons.school_rounded
                                                        ),
                                                        (
                                                          '工作搭子',
                                                          '同事',
                                                          Icons.work_rounded
                                                        ),
                                                        (
                                                          '邻家大叔',
                                                          '邻家大叔',
                                                          Icons.coffee_outlined
                                                        ),
                                                        (
                                                          '弟弟',
                                                          '弟弟',
                                                          Icons
                                                              .emoji_emotions_outlined
                                                        ),
                                                        (
                                                          '闺蜜',
                                                          '闺蜜',
                                                          Icons
                                                              .favorite_border_rounded
                                                        ),
                                                        (
                                                          '好兄弟',
                                                          '好兄弟',
                                                          Icons
                                                              .handshake_outlined
                                                        ),
                                                        (
                                                          '学姐',
                                                          '学姐',
                                                          Icons.school_outlined
                                                        ),
                                                        (
                                                          '学长',
                                                          '学长',
                                                          Icons
                                                              .menu_book_outlined
                                                        ),
                                                        (
                                                          '树洞搭子',
                                                          '树洞搭子',
                                                          Icons
                                                              .chat_bubble_outline_rounded
                                                        ),
                                                        (
                                                          '运动搭子',
                                                          '运动搭子',
                                                          Icons
                                                              .directions_run_rounded
                                                        )
                                                      ])
                                                        ChoiceChip(
                                                            avatar: Icon(icon,
                                                                size: 16,
                                                                color: _roleType
                                                                            .text ==
                                                                        type
                                                                    ? BingoPalette
                                                                        .primary
                                                                    : BingoPalette
                                                                        .muted),
                                                            label: Text(label,
                                                                style:
                                                                    const TextStyle(
                                                                        fontSize:
                                                                            11)),
                                                            selected: _roleType
                                                                    .text ==
                                                                type,
                                                            showCheckmark:
                                                                false,
                                                            selectedColor:
                                                                BingoPalette
                                                                    .blush,
                                                            onSelected: (_) =>
                                                                setState(() =>
                                                                    _roleType
                                                                            .text =
                                                                        type))
                                                    ]),
                                                const SizedBox(height: 9),
                                                TextFormField(
                                                    controller: _roleType,
                                                    maxLength: 30,
                                                    decoration:
                                                        const InputDecoration(
                                                            hintText:
                                                                '也可以自定义搭子身份',
                                                            counterText: ''))
                                              ],
                                              const SizedBox(height: 12),
                                              ExpansionTile(
                                                  tilePadding: EdgeInsets.zero,
                                                  initiallyExpanded: _builtin,
                                                  title: const Text('搭子性格',
                                                      style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w800)),
                                                  children: [
                                                    Wrap(
                                                        spacing: 7,
                                                        runSpacing: 6,
                                                        children: [
                                                          for (final p
                                                              in _personalities)
                                                            ChoiceChip(
                                                                label: Text(p,
                                                                    style: const TextStyle(
                                                                        fontSize:
                                                                            12)),
                                                                selected:
                                                                    _personality ==
                                                                        p,
                                                                selectedColor:
                                                                    BingoPalette
                                                                        .blush,
                                                                showCheckmark:
                                                                    false,
                                                                onSelected: (_) =>
                                                                    setState(() =>
                                                                        _personality =
                                                                            p))
                                                        ])
                                                  ]),
                                              if (!_builtin)
                                                ExpansionTile(
                                                    tilePadding:
                                                        EdgeInsets.zero,
                                                    title: const Text('陪伴特征',
                                                        style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800)),
                                                    children: [_traitPicker()]),
                                              if (_error != null)
                                                Text(_error!,
                                                    style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error)),
                                              if (_busy)
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            12),
                                                    child: Text(_progress))
                                            ])))
                              ])))),
              bottomNavigationBar: SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                      child: FilledButton(
                          onPressed: _busy ? null : _save,
                          style: FilledButton.styleFrom(
                              backgroundColor: BingoPalette.primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 54)),
                          child: Text(widget.role == null ? '创建搭子' : '保存修改',
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)))))),
          if (_cloning)
            Positioned.fill(child: VoiceCloneProgress(message: _progress))
        ]));
  }
}
