import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';

enum _AuthMode { login, register }

class AuthPage extends StatefulWidget {
  const AuthPage({
    required this.gateway,
    required this.onAuthenticated,
    super.key,
  });

  final AuthGateway gateway;
  final ValueChanged<AuthResult> onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  bool _obscurePassword = true;
  bool _agreed = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _comingSoon() => showCenterToast(context, '敬请期待');

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_agreed) {
      showCenterToast(context, '请先阅读并同意用户协议和隐私政策');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = _mode == _AuthMode.login
          ? await widget.gateway
              .login(_phoneController.text.trim(), _passwordController.text)
          : await widget.gateway
              .register(_phoneController.text.trim(), _passwordController.text);
      if (mounted) widget.onAuthenticated(result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) setState(() => _error = '无法连接服务端，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLogin = _mode == _AuthMode.login;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned(
            top: -150,
            left: -110,
            child: _BackgroundGlow(size: 310),
          ),
          const Positioned(
            top: 95,
            right: -150,
            child: _BackgroundGlow(size: 280),
          ),
          const Positioned(
            bottom: -180,
            left: -150,
            child: _BackgroundGlow(size: 310),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 128,
                            height: 128,
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(38),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x17205F4F),
                                  blurRadius: 32,
                                  offset: Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(31),
                              child:
                                  Image.asset('assets/images/bingo_logo.png'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          isLogin ? '欢迎回来' : '创建 Bingo 账号',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          isLogin ? '登录后继续使用 Bingo' : '注册后开启你的 Bingo 之旅',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF788390),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 30),
                        _modeSelector(),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: InputDecoration(
                            hintText: '请输入手机号',
                            prefixIcon: SizedBox(
                              width: 102,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.phone_android_rounded,
                                      size: 20),
                                  const SizedBox(width: 7),
                                  const Text('+86',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 10),
                                  Container(
                                    width: 1,
                                    height: 22,
                                    color: BingoPalette.line,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          validator: (value) {
                            final phone = value?.trim() ?? '';
                            if (!RegExp(r'^\+?[0-9]{6,20}$').hasMatch(phone)) {
                              return '请输入有效手机号';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: isLogin
                              ? const [AutofillHints.password]
                              : const [AutofillHints.newPassword],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: '请输入密码',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              (value?.length ?? 0) < 8 ? '密码至少需要 8 位' : null,
                        ),
                        if (isLogin)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _comingSoon,
                              child: const Text('忘记密码？'),
                            ),
                          )
                        else
                          const SizedBox(height: 18),
                        if (_error case final error?) ...[
                          const SizedBox(height: 6),
                          Text(error, style: TextStyle(color: colors.error)),
                          const SizedBox(height: 10),
                        ],
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: BingoPalette.brandGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x3020A077),
                                blurRadius: 22,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              minimumSize: const Size.fromHeight(58),
                            ),
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isLogin ? '登录' : '注册并继续',
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(Icons.arrow_forward_rounded),
                                    ],
                                  ),
                          ),
                        ),
                        if (isLogin) ...[
                          const SizedBox(height: 26),
                          const Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14),
                                child: Text(
                                  '或使用其他方式登录',
                                  style: TextStyle(color: Color(0xFF788390)),
                                ),
                              ),
                              Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: InkWell(
                              onTap: _comingSoon,
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.all(5),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: BingoPalette.line),
                                      ),
                                      child: const Icon(
                                        Icons.sms_outlined,
                                        color: Color(0xFF687783),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      '验证码登录',
                                      style:
                                          TextStyle(color: Color(0xFF788390)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        _agreement(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSelector() => Container(
        height: 54,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0xFFEDF5F2),
          borderRadius: BorderRadius.circular(27),
        ),
        child: Row(
          children: [
            for (final (mode, label) in const [
              (_AuthMode.login, '登录'),
              (_AuthMode.register, '注册'),
            ])
              Expanded(
                child: InkWell(
                  onTap: _submitting
                      ? null
                      : () => setState(() {
                            _mode = mode;
                            _error = null;
                          }),
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _mode == mode ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: _mode == mode
                          ? const [
                              BoxShadow(
                                color: Color(0x14205F4F),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: _mode == mode
                            ? BingoPalette.blue
                            : const Color(0xFF788390),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _agreement() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _agreed,
            onChanged: (value) => setState(() => _agreed = value ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('我已阅读并同意'),
                  _agreementLink('《用户协议》'),
                  const Text('和'),
                  _agreementLink('《隐私政策》'),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _agreementLink(String label) => InkWell(
        onTap: _comingSoon,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            style: const TextStyle(
              color: BingoPalette.blue,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Color(0x3667CDAE), Color(0x0067CDAE)],
          ),
        ),
      );
}
