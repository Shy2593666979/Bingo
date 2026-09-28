import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

enum _AuthMode { login, register }

class AuthPage extends StatefulWidget {
  const AuthPage(
      {required this.gateway, required this.onAuthenticated, super.key});

  final AuthGateway gateway;
  final ValueChanged<AuthResult> onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  _AuthMode _mode = _AuthMode.register;
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BingoPalette.softGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(color: Colors.white),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x172B4480),
                        blurRadius: 36,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: Container(
                            width: 118,
                            height: 118,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(34),
                              boxShadow: const [
                                BoxShadow(
                                    color: Color(0x263478F6), blurRadius: 28),
                              ],
                            ),
                            child: Image.asset('assets/images/bingo_logo.png'),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _mode == _AuthMode.login ? '欢迎回来' : '创建 Bingo 账号',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          height: 50,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF1F8),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              for (final entry in const [
                                (_AuthMode.login, '登录'),
                                (_AuthMode.register, '注册'),
                              ])
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _submitting
                                        ? null
                                        : () => setState(() {
                                              _mode = entry.$1;
                                              _error = null;
                                            }),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _mode == entry.$1
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: _mode == entry.$1
                                            ? const [
                                                BoxShadow(
                                                  color: Color(0x14243B72),
                                                  blurRadius: 10,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Text(
                                        entry.$2,
                                        style: TextStyle(
                                          color: _mode == entry.$1
                                              ? BingoPalette.blue
                                              : const Color(0xFF7A829B),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: const InputDecoration(
                            labelText: '手机号',
                            prefixIcon: Icon(Icons.phone_android_rounded),
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
                          autofillHints: _mode == _AuthMode.login
                              ? const [AutofillHints.password]
                              : const [AutofillHints.newPassword],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: '密码',
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
                        if (_error case final error?) ...[
                          const SizedBox(height: 12),
                          Text(error, style: TextStyle(color: colors.error)),
                        ],
                        const SizedBox(height: 22),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: BingoPalette.brandGradient,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x293478F6), blurRadius: 20),
                            ],
                          ),
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                            ),
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(
                                    _mode == _AuthMode.login
                                        ? Icons.arrow_forward_rounded
                                        : Icons.person_add_alt_1_rounded,
                                  ),
                            label:
                                Text(_mode == _AuthMode.login ? '登录' : '注册并继续'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
