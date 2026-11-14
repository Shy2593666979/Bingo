import 'package:bingo/core/design/bingo_page.dart';
import 'package:bingo/features/voices/data/voice_gateway.dart';
import 'package:bingo/features/voices/models/voice_option.dart';
import 'package:bingo/features/voices/presentation/voice_cover.dart';
import 'package:bingo/features/voices/presentation/voice_editor_page.dart';
import 'package:bingo/features/voices/presentation/voice_library_page.dart';
import 'dart:async';
import 'dart:convert';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/avatar_crop_page.dart';
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
  final _editorScroll = ScrollController();
  late final TextEditingController _name;
  late final TextEditingController _background;
  late final TextEditingController _speakingStyle;
  late final TextEditingController _description;
  late final TextEditingController _roleType;
  bool get _builtin => widget.role != null && !widget.role!.identityEditable;
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
  int _step = 0;
  bool get _wizard => widget.role == null;
  static const _steps = [
    '认识你的新搭子',
    '找到喜欢的聊天语气',
    '让 TA 更有个性',
    '一起补全 TA 的故事',
    '为 TA 选择一个声音'
  ];
  void _changeStep(int step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editorScroll.hasClients) _editorScroll.jumpTo(0);
    });
  }

  void _advance() {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    if (_step == 2 && (_traits.length < 2 || _traits.length > 3)) {
      showCenterToast(context, '请选择 2～3 个性格标签');
      return;
    }
    if (_step < 4) {
      _changeStep(_step + 1);
    } else {
      _save();
    }
  }

  Widget _stepHeader() => Column(children: [
        Row(children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
                child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                        color: i <= _step
                            ? BingoPalette.primary
                            : BingoPalette.line,
                        borderRadius: BorderRadius.circular(3)))),
          ]
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: Text(_steps[_step],
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w500))),
          Text('${_step + 1} / 5',
              style: const TextStyle(fontSize: 12, color: BingoPalette.muted)),
        ]),
        const SizedBox(height: 6),
        Align(
            alignment: Alignment.centerLeft,
            child: Text(
                const [
                  '从一个名字开始，认识你的新搭子。',
                  '选择你喜欢的表达方式，也可以自由描述。',
                  '选出最能代表 TA 的 2～3 个标签。',
                  '写下 TA 的经历、喜好，以及你们的相处方式。',
                  '选一个喜欢的声音，让陪伴更有温度。',
                ][_step],
                style: const TextStyle(
                    fontSize: 13, height: 1.6, color: BingoPalette.muted))),
        const SizedBox(height: 12),
      ]);
  bool _playing = false;
  bool _expandedTraits = false;
  String _progress = '';
  List<VoiceOption> _voices = [];
  int _previewGeneration = 0;
  VoiceGateway? get _voiceGateway =>
      widget.gateway is VoiceGateway ? widget.gateway as VoiceGateway : null;
  late List<String> _traits;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _role = widget.role;
    _traits = List.of(widget.role?.traits ?? ['善于倾听', '陪伴聊天']);
    _name = TextEditingController(text: widget.role?.displayName);
    _roleType =
        TextEditingController(text: widget.role?.relationship ?? '陪伴伙伴');
    _speakingStyle =
        TextEditingController(text: widget.role?.speakingStyle ?? '温柔体贴');
    _background = TextEditingController(text: widget.role?.background);
    _description = TextEditingController(text: widget.role?.description);
    _avatarData = widget.role?.avatarData;
    _voiceId = widget.role?.voiceId;
    _loadVoices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _previewGeneration++;
      unawaited(_device.invokeMethod<void>('stopPreviewAudio'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_device.invokeMethod<void>('stopPreviewAudio'));
    _previewGeneration++;
    _name.dispose();
    _background.dispose();
    _speakingStyle.dispose();
    _description.dispose();
    _roleType.dispose();
    _editorScroll.dispose();
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
          ? (_background.text.trim().isEmpty
              ? '陪伴用户自然交流。'
              : _background.text.trim())
          : _background.text.trim(),
      background: _builtin ? null : _background.text.trim(),
      speakingStyle: _speakingStyle.text.trim(),
      relationship: _roleType.text.trim(),
      personalityTags: _traits,
      roleType: _roleType.text.trim(),
      description: _description.text.trim(),
      personality: _personalities.contains(_speakingStyle.text.trim())
          ? _speakingStyle.text.trim()
          : null,
      avatarData: _avatarData,
      voiceId: _voiceId,
      draft: draft,
      traits: _traits,
    );
    _role = result;
    return result;
  }

  Future<void> _loadVoices() async {
    final gateway = _voiceGateway;
    if (gateway == null) return;
    try {
      final voices = await gateway.listVoices();
      if (mounted) {
        setState(() {
          _voices = voices;
          _voiceId ??= voices
              .where((voice) => voice.ready && voice.scope == 'system')
              .firstOrNull
              ?.id;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = error is ApiException ? error.message : '音色库加载失败，请重试');
      }
    }
  }

  Future<void> _pickVoice() async {
    final gateway = _voiceGateway;
    if (gateway == null) return;
    _previewGeneration++;
    await _device.invokeMethod<void>('stopPreviewAudio');
    if (!mounted) return;
    final voice = await Navigator.of(context).push<VoiceOption>(
        MaterialPageRoute(
            builder: (_) => VoiceLibraryPage(
                gateway: gateway, picking: true, selectedId: _voiceId)));
    if (!mounted) return;
    if (voice != null) {
      setState(() {
        _voiceId = voice.id;
        _playing = false;
      });
    }
    await _loadVoices();
  }

  Future<void> _record() async {
    final gateway = _voiceGateway;
    if (gateway == null) return;
    _previewGeneration++;
    await _device.invokeMethod<void>('stopPreviewAudio');
    if (!mounted) return;
    final voice = await Navigator.of(context).push<VoiceOption>(
        MaterialPageRoute(builder: (_) => VoiceEditorPage(gateway: gateway)));
    if (!mounted) return;
    if (voice?.ready == true) setState(() => _voiceId = voice!.id);
    await _loadVoices();
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
      final generation = ++_previewGeneration;
      final audio = await _voiceGateway!.previewVoice(voiceId);
      if (!mounted || generation != _previewGeneration) return;
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
      showCenterToast(context, '请选择 2～3 个性格标签');
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
            child: Text('选择 2～3 个性格标签',
                style: TextStyle(fontSize: 12, color: BingoPalette.muted))),
        Text('已选 ${_traits.length} / 3',
            style: const TextStyle(fontSize: 11, color: BingoPalette.muted)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 7, runSpacing: 8, children: [
        for (final label in visible)
          Semantics(
              button: true,
              selected: _traits.contains(label),
              child: Material(
                  color: _traits.contains(label)
                      ? const Color(0xFFF7ECE7)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: _traits.contains(label)
                              ? BingoPalette.primary.withValues(alpha: .3)
                              : BingoPalette.line)),
                  child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        if (!_traits.contains(label) && _traits.length >= 3) {
                          showCenterToast(context, '最多选择 3 个性格标签');
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
                                    fontSize: 11, color: BingoPalette.muted)),
                          ]))))),
      ]),
      TextButton(
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          onPressed: () => setState(() => _expandedTraits = !_expandedTraits),
          child: Text(_expandedTraits ? '收起更多标签' : '展开更多标签',
              style: const TextStyle(fontSize: 12))),
    ]);
  }

  Widget _voicePicker(String voiceLabel) {
    final chosen = _voices.where((voice) => voice.id == _voiceId).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Material(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
              key: const ValueKey('voice-selector'),
              onTap: _pickVoice,
              leading: chosen == null
                  ? const Icon(Icons.graphic_eq_rounded)
                  : VoiceCover(id: chosen.id, size: 40),
              title: Text(chosen?.name ?? '选择音色',
                  style: const TextStyle(fontSize: 15)),
              subtitle: const Text('从独立音色库中选择',
                  style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
              trailing: const Icon(Icons.chevron_right_rounded))),
      Row(children: [
        Expanded(
            child: Text('当前音色：$voiceLabel',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF737373)))),
        TextButton.icon(
            onPressed: _voiceId == null ? null : _preview,
            icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 18),
            label: Text(_playing ? '停止试听' : '试听')),
      ]),
      TextButton.icon(
          onPressed: _record,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('创建新音色')),
    ]);
  }

  Widget _label(String title) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 9),
      child: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));
  Widget _field({
    required String keyName,
    required TextEditingController controller,
    required String hint,
    required int limit,
    int lines = 1,
    bool editable = true,
    bool requiredValue = true,
  }) =>
      TextFormField(
          key: ValueKey(keyName),
          controller: controller,
          readOnly: !editable,
          minLines: lines,
          maxLines: lines + (lines > 1 ? 2 : 0),
          maxLength: limit,
          decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              filled: true,
              fillColor: BingoPalette.softSurface,
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFF0F0F0))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: BingoPalette.primary))),
          validator: requiredValue && editable
              ? (value) => (value?.trim().isEmpty ?? true) ? '请填写此项人物资料' : null
              : null);

  @override
  Widget build(BuildContext context) {
    final voiceLabel =
        _voices.where((voice) => voice.id == _voiceId).firstOrNull?.name ??
            widget.role?.voiceName ??
            '尚未选择';
    return PopScope(
      canPop: !_busy && (!_wizard || _step == 0),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && _wizard && _step > 0) _changeStep(_step - 1);
      },
      child: Stack(children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
              centerTitle: true,
              leading: _wizard && _step > 0
                  ? IconButton(
                      tooltip: '上一步',
                      onPressed: _busy ? null : () => _changeStep(_step - 1),
                      icon: const Icon(Icons.arrow_back_rounded))
                  : null,
              title: Text(widget.role == null ? '创建搭子' : '编辑搭子')),
          body: SafeArea(
              top: false,
              child: AbsorbPointer(
                  absorbing: _busy,
                  child: Form(
                      key: _form,
                      child: ListView(
                          controller: _editorScroll,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          children: [
                            if (_wizard) _stepHeader(),
                            Material(
                                color:
                                    _wizard ? Colors.transparent : Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                child: Padding(
                                    padding: EdgeInsets.all(_wizard ? 0 : 16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (!_wizard || _step == 0) ...[
                                            if (!_wizard)
                                              const Text('人物头像',
                                                  style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            const SizedBox(height: 12),
                                            Align(
                                                alignment: _wizard
                                                    ? Alignment.center
                                                    : Alignment.centerLeft,
                                                child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16),
                                                    child: InkWell(
                                                        onTap: _builtin
                                                            ? null
                                                            : _chooseAvatar,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(16),
                                                        child: _builtin
                                                            ? AssistantAvatar(
                                                                role: widget
                                                                    .role!.name,
                                                                size: 80)
                                                            : _avatarData !=
                                                                    null
                                                                ? UserAvatar(
                                                                    avatarData:
                                                                        _avatarData,
                                                                    size: 80)
                                                                : Container(
                                                                    width: 80,
                                                                    height: 80,
                                                                    decoration: BoxDecoration(
                                                                        color: BingoPalette
                                                                            .softSurface,
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                                16),
                                                                        border: Border.all(
                                                                            color: BingoPalette.primary.withValues(
                                                                                alpha:
                                                                                    .4))),
                                                                    child: const Column(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.center,
                                                                        children: [
                                                                          Icon(
                                                                              Icons.add_rounded,
                                                                              color: BingoPalette.primary),
                                                                          SizedBox(
                                                                              height: 4),
                                                                          Text(
                                                                              '上传头像',
                                                                              style: TextStyle(fontSize: 10, color: BingoPalette.primary))
                                                                        ]))))),
                                            _label('人物名称'),
                                            _field(
                                                keyName: 'role-name',
                                                controller: _name,
                                                hint: '给 TA 起一个亲切的名字',
                                                limit: 30,
                                                editable: !_builtin),
                                            _label('人物关系'),
                                            if (!_builtin && !_wizard) ...[
                                              Wrap(
                                                  spacing: 7,
                                                  runSpacing: 6,
                                                  children: [
                                                    for (final relation in [
                                                      '陪伴伙伴',
                                                      '女朋友',
                                                      '男朋友',
                                                      '老师',
                                                      '同事',
                                                      '邻家大叔',
                                                      '弟弟',
                                                      '闺蜜',
                                                      '好兄弟',
                                                      '学姐',
                                                      '学长',
                                                      '树洞搭子',
                                                      '运动搭子'
                                                    ])
                                                      ChoiceChip(
                                                          label: Text(relation,
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          11)),
                                                          selected:
                                                              _roleType.text ==
                                                                  relation,
                                                          showCheckmark: false,
                                                          selectedColor:
                                                              BingoPalette
                                                                  .blush,
                                                          onSelected: (_) =>
                                                              setState(() =>
                                                                  _roleType
                                                                          .text =
                                                                      relation)),
                                                  ]),
                                              const SizedBox(height: 10),
                                            ],
                                            _field(
                                                keyName: 'role-relationship',
                                                controller: _roleType,
                                                hint: '选择或填写 TA 与你的关系',
                                                limit: 30,
                                                editable: !_builtin),
                                          ],
                                          if (!_wizard || _step == 1) ...[
                                            _label('说话风格'),
                                            Wrap(
                                                spacing: 7,
                                                runSpacing: 6,
                                                children: [
                                                  for (final style
                                                      in _personalities)
                                                    ChoiceChip(
                                                        label: Text(style,
                                                            style:
                                                                const TextStyle(
                                                                    fontSize:
                                                                        12)),
                                                        selected: _speakingStyle
                                                                .text ==
                                                            style,
                                                        showCheckmark: false,
                                                        selectedColor:
                                                            BingoPalette.blush,
                                                        onSelected: (_) =>
                                                            setState(() =>
                                                                _speakingStyle
                                                                        .text =
                                                                    style)),
                                                ]),
                                            const SizedBox(height: 10),
                                            _field(
                                                keyName: 'role-speaking-style',
                                                controller: _speakingStyle,
                                                hint: '例如：口语自然、简洁幽默，先倾听再给建议',
                                                limit: 1000,
                                                lines: 3),
                                            if (_builtin)
                                              const Padding(
                                                  padding:
                                                      EdgeInsets.only(top: 10),
                                                  child: Text(
                                                      '说话风格仅对你生效，共享搭子的其他人物资料保持一致。',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: BingoPalette
                                                              .muted))),
                                          ],
                                          if (!_wizard || _step == 2) ...[
                                            _label('性格标签'),
                                            if (_builtin)
                                              Wrap(
                                                  spacing: 7,
                                                  runSpacing: 7,
                                                  children: _traits
                                                      .map((label) =>
                                                          TraitBadge(label,
                                                              outlined: true))
                                                      .toList())
                                            else
                                              _traitPicker(),
                                          ],
                                          if (!_wizard || _step == 3) ...[
                                            _label('人物背景'),
                                            _field(
                                                keyName: 'role-background',
                                                controller: _background,
                                                hint:
                                                    '描述 TA 的经历、职业、兴趣，以及你们如何认识',
                                                limit: 2000,
                                                lines: 4,
                                                editable: !_builtin),
                                          ],
                                          if (!_wizard || _step == 4) ...[
                                            _label('人物声音'),
                                            _voicePicker(voiceLabel),
                                            if (!_builtin)
                                              ExpansionTile(
                                                  tilePadding: EdgeInsets.zero,
                                                  title: const Text('更多资料',
                                                      style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500)),
                                                  children: [
                                                    _label('一句话介绍'),
                                                    _field(
                                                        keyName:
                                                            'role-description',
                                                        controller:
                                                            _description,
                                                        hint: '用一句话描述你的搭子',
                                                        limit: 200,
                                                        requiredValue: false),
                                                  ]),
                                          ],
                                          if (_error != null)
                                            Text(_error!,
                                                style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error)),
                                          if (_busy)
                                            Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Text(_progress)),
                                        ]))),
                          ])))),
          bottomNavigationBar: BingoActionBar(
              child: FilledButton(
                  onPressed: _busy
                      ? null
                      : _wizard
                          ? _advance
                          : _save,
                  style: FilledButton.styleFrom(
                      backgroundColor: BingoPalette.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: Text(_wizard ? (_step < 4 ? '下一步' : '创建搭子') : '保存修改',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)))),
        ),
      ]),
    );
  }
}
