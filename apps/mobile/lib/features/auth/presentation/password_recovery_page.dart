import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showRecoveryCode(BuildContext context, String code) => showDialog<
        void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
            title: const Text('请保存你的恢复码'),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('找回密码时需要用户昵称、生日和此恢复码。恢复码只展示这一次，请存入密码管理器，不要分享给别人。'),
                  const SizedBox(height: 18),
                  SelectableText(code,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
            actions: [
              TextButton(
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  child: const Text('复制恢复码')),
              FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('我已妥善保存'))
            ])));

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage(
      {required this.gateway, this.onPasswordChanged, super.key});
  final AccountGateway gateway;
  final VoidCallback? onPasswordChanged;
  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  DateTime? _birthday;
  bool _busy = false;
  String? _error;
  bool get _changing => widget.onPasswordChanged != null;
  @override
  void dispose() {
    for (final controller in [_phone, _username, _code, _password, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_changing && _birthday == null) {
      setState(() => _error = '请选择注册时填写的生日');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_changing) {
        await widget.gateway.changePassword(_code.text, _password.text);
        if (mounted) {
          Navigator.pop(context);
          widget.onPasswordChanged!();
        }
      } else {
        final code = await widget.gateway.resetPassword(
            phone: _phone.text.trim(),
            username: _username.text.trim(),
            birthday: _birthday!,
            recoveryCode: _code.text.trim(),
            newPassword: _password.text);
        if (!mounted) return;
        await showRecoveryCode(context, code);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('密码已重置，请重新登录')));
          Navigator.pop(context);
        }
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) setState(() => _error = '操作失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(_changing ? '修改密码' : '找回密码')),
      body: DecoratedBox(
          decoration: const BoxDecoration(gradient: BingoPalette.softGradient),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_changing ? '设置一个新的登录密码' : '验证你的账号信息',
                          style: const TextStyle(
                              fontSize: 25, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Text(
                          _changing
                              ? '修改成功后，所有设备需要重新登录。'
                              : '生日不能单独证明身份，还需要你保存的恢复码。',
                          style: const TextStyle(color: Color(0xFF7D918A))),
                      const SizedBox(height: 24),
                      if (!_changing) ...[
                        _field(_phone, '注册手机号'),
                        _field(_username, '用户昵称'),
                        OutlinedButton.icon(
                            icon: const Icon(Icons.cake_outlined),
                            label: Text(
                                _birthday?.toIso8601String().substring(0, 10) ??
                                    '选择生日'),
                            onPressed: _busy
                                ? null
                                : () async {
                                    final date = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime(2000),
                                        firstDate: DateTime(1900),
                                        lastDate: DateTime.now());
                                    if (date != null && mounted) {
                                      setState(() => _birthday = date);
                                    }
                                  }),
                        const SizedBox(height: 14),
                      ],
                      _field(_code, _changing ? '当前密码' : '恢复码', secret: true),
                      _field(_password, '新密码（至少 8 位）',
                          secret: true, minLength: 8),
                      _field(_confirm, '再次输入新密码', secret: true, confirm: true),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(_busy
                              ? '正在验证…'
                              : _changing
                                  ? '确认修改'
                                  : '验证并重置密码')),
                    ]))
          ])));
  Widget _field(TextEditingController controller, String label,
          {bool secret = false, int minLength = 1, bool confirm = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
              controller: controller,
              obscureText: secret,
              enabled: !_busy,
              decoration: InputDecoration(labelText: label),
              validator: (value) => confirm && value != _password.text
                  ? '两次密码不一致'
                  : (value?.length ?? 0) < minLength
                      ? '请填写有效信息'
                      : null));
}
