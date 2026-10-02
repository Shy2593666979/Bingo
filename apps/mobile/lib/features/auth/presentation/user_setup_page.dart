import 'dart:convert';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/avatar_crop_page.dart';
import 'package:bingo/features/auth/presentation/password_recovery_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UserSetupPage extends StatefulWidget {
  const UserSetupPage({
    required this.gateway,
    required this.profile,
    required this.onSaved,
    this.isEditing = false,
    super.key,
  });

  final UserDetailsGateway gateway;
  final UserProfile profile;
  final ValueChanged<UserProfile> onSaved;
  final bool isEditing;

  @override
  State<UserSetupPage> createState() => _UserSetupPageState();
}

class _UserSetupPageState extends State<UserSetupPage> {
  static const _device = MethodChannel('bingo/device_tools');
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  DateTime? _birthday;
  String? _gender;
  String? _avatarData;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.profile.username);
    _birthday = DateTime.tryParse(widget.profile.birthday ?? '');
    _gender = widget.profile.gender;
    _avatarData = widget.profile.userAvatarData;
  }

  @override
  void dispose() {
    _nickname.dispose();
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
      if (mounted && image != null) {
        setState(() => _avatarData = base64Encode(image));
      }
    } on Exception {
      if (mounted) showCenterToast(context, '无法打开相册，请重试');
    }
  }

  Future<void> _chooseBirthday() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    var selected = _birthday ?? DateTime(2000, 1, 1);
    final result = await showModalBottomSheet<DateTime>(
        context: context,
        backgroundColor: Colors.white,
        showDragHandle: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: 310,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消')),
                        const Expanded(
                            child: Text('选择生日',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700))),
                        TextButton(
                            onPressed: () => Navigator.pop(context, selected),
                            child: const Text('确定')),
                      ])),
                  Expanded(
                      child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    dateOrder: DatePickerDateOrder.ymd,
                    initialDateTime: selected,
                    minimumDate: DateTime(1900),
                    maximumDate: DateTime(now.year, now.month, now.day),
                    onDateTimeChanged: (value) => selected = value,
                  )),
                ]))));
    if (mounted && result != null) setState(() => _birthday = result);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_gender == null || _birthday == null) {
      showCenterToast(context, '请选择性别和生日');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.saveUserDetails(
          nickname: _nickname.text.trim(),
          gender: _gender!,
          birthday: _birthday!,
          avatarData: _avatarData);
      if (!mounted) return;
      if (result.recoveryCode != null) {
        await showRecoveryCode(context, result.recoveryCode!);
      }
      if (mounted) widget.onSaved(result.user);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) setState(() => _error = '保存失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: widget.isEditing
          ? AppBar(title: const Text('个人资料'), centerTitle: true)
          : null,
      body: Container(
          decoration: const BoxDecoration(gradient: BingoPalette.softGradient),
          child: SafeArea(
              child: Form(
                  key: _form,
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                      children: [
                        Text(widget.isEditing ? '个人资料' : '完善个人资料',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 25, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        const Text('让 Bingo 从认识你开始',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 28),
                        Center(
                            child: Semantics(
                                label: '选择用户头像',
                                button: true,
                                child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: _busy ? null : _chooseAvatar,
                                    child: Stack(children: [
                                      UserAvatar(
                                          avatarData: _avatarData, size: 96),
                                      Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                  color:
                                                      BingoPalette.avatarButton,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                      color: Colors.white,
                                                      width: 3)),
                                              child: const Icon(
                                                  Icons.camera_alt_outlined,
                                                  size: 18,
                                                  color: BingoPalette
                                                      .avatarButtonInk)))
                                    ])))),
                        const SizedBox(height: 10),
                        const Text('点击更换头像',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 28),
                        _card(
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: TextFormField(
                                    controller: _nickname,
                                    enabled: !_busy,
                                    maxLength: 30,
                                    textInputAction: TextInputAction.done,
                                    decoration: const InputDecoration(
                                        labelText: '用户昵称',
                                        hintText: '希望我们怎么称呼你',
                                        counterText: '',
                                        prefixIcon: Icon(Icons.person_outline)),
                                    validator: (value) =>
                                        value == null || value.trim().isEmpty
                                            ? '请输入昵称'
                                            : null))),
                        const SizedBox(height: 16),
                        _card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('用户性别',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 12),
                                      Row(children: [
                                        for (final gender in ['男', '女', '不愿透露'])
                                          Expanded(
                                              child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(horizontal: 3),
                                                  child: ChoiceChip(
                                                      label: Center(
                                                          child: Text(gender)),
                                                      showCheckmark: false,
                                                      selected:
                                                          _gender == gender,
                                                      onSelected: _busy
                                                          ? null
                                                          : (_) => setState(
                                                              () => _gender =
                                                                  gender))))
                                      ])
                                    ]))),
                        const SizedBox(height: 16),
                        _card(
                            child: ListTile(
                                enabled: !_busy,
                                leading: const Icon(Icons.cake_outlined,
                                    color: BingoPalette.blue),
                                title: const Text('用户生日'),
                                subtitle: Text(_birthday == null
                                    ? '请选择生日'
                                    : '${_birthday!.year}年${_birthday!.month}月${_birthday!.day}日'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _busy ? null : _chooseBirthday)),
                        const SizedBox(height: 12),
                        const Text('昵称与生日用于核对账号找回信息，请认真填写。',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                        ],
                        const SizedBox(height: 28),
                        FilledButton(
                            onPressed: _busy ? null : _save,
                            child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                child: Text(_busy
                                    ? '正在保存…'
                                    : widget.isEditing
                                        ? '保存资料'
                                        : '完成，开始体验'))),
                      ])))));

  Widget _card({required Widget child}) => Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: BingoPalette.line)),
      child: child);
}
