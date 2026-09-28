import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({
    required this.gateway,
    required this.profile,
    required this.onSaved,
    this.onCancel,
    super.key,
  });

  final AuthGateway gateway;
  final UserProfile profile;
  final ValueChanged<UserProfile> onSaved;
  final VoidCallback? onCancel;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _assistantNameController;
  ProfileOptions? _options;
  String? _role;
  String? _personality;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.profile.username);
    _assistantNameController =
        TextEditingController(text: widget.profile.assistantName ?? 'Bingo');
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final options = await widget.gateway.getProfileOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        _role = options.roles.contains(widget.profile.role)
            ? widget.profile.role
            : (options.roles.isNotEmpty ? options.roles.first : null);
        _personality =
            options.personalities.contains(widget.profile.personality)
                ? widget.profile.personality
                : (options.personalities.isNotEmpty
                    ? options.personalities.first
                    : null);
        _error = null;
      });
    } on Exception {
      if (mounted) setState(() => _error = '无法加载助手选项，请重试');
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final role = _role;
    final personality = _personality;
    if (role == null || personality == null) {
      setState(() => _error = '请先选择助手角色和性格');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await widget.gateway.updateProfile(
        username: _usernameController.text.trim(),
        assistantName: _assistantNameController.text.trim(),
        personality: personality,
        role: role,
      );
      if (mounted) widget.onSaved(profile);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) setState(() => _error = '保存失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _requiredName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return '此项不能为空';
    if (name.length > 30) return '最多输入 30 个字符';
    return null;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _assistantNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    return Scaffold(
      backgroundColor: BingoPalette.ice,
      body: Stack(
        children: [
          const Positioned.fill(
              child: DecoratedBox(
                  decoration:
                      BoxDecoration(gradient: BingoPalette.softGradient))),
          const Positioned(top: 70, right: -90, child: _SoftCircle(size: 210)),
          const Positioned(top: 180, left: -105, child: _SoftCircle(size: 170)),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 32),
              children: [
                _buildHeader(context),
                const SizedBox(height: 8),
                _buildIntro(),
                const SizedBox(height: 22),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _ProfileTextCard(
                        label: '你的用户名',
                        icon: const Icon(Icons.person_outline_rounded,
                            color: BingoPalette.blue, size: 25),
                        controller: _usernameController,
                        validator: _requiredName,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      _ProfileTextCard(
                        label: '助手名称',
                        icon: const _AssistantNameIcon(),
                        controller: _assistantNameController,
                        validator: _requiredName,
                        textInputAction: TextInputAction.done,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (options == null && _error == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (options != null) ...[
                  _ProfileDropdown(
                    key: ValueKey('role-$_role'),
                    label: '助手角色',
                    icon: const _RoleIcon(),
                    iconBackgroundColor: const Color(0xFFECFBF6),
                    value: _role,
                    options: options.roles,
                    onSelected: (value) => setState(() => _role = value),
                  ),
                  const SizedBox(height: 12),
                  _ProfileDropdown(
                    key: ValueKey('personality-$_personality'),
                    label: '助手性格',
                    icon: const _PersonalityIcon(),
                    value: _personality,
                    options: options.personalities,
                    onSelected: (value) => setState(() => _personality = value),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  if (options == null)
                    TextButton(
                        onPressed: _loadOptions, child: const Text('重试')),
                ],
                const SizedBox(height: 22),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: BingoPalette.brandGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: BingoPalette.blue.withValues(alpha: 0.16),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: FilledButton(
                    onPressed: _saving || options == null ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('保存并继续',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 23),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => SizedBox(
        height: 56,
        child: Row(
          children: [
            if (widget.onCancel != null)
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
            Text(
              '个性化设置',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: BingoPalette.ink,
                  ),
            ),
          ],
        ),
      );

  Widget _buildIntro() => Column(
        children: [
          SizedBox(
            height: 118,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned(
                  right: 15,
                  top: 42,
                  child: Icon(Icons.favorite_rounded,
                      color: Color(0xFFFFDED9), size: 32),
                ),
                Center(
                  child: SizedBox.square(
                    dimension: 118,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      BingoPalette.blue.withValues(alpha: 0.07),
                                  blurRadius: 22,
                                  offset: const Offset(0, 7),
                                ),
                              ],
                            ),
                            child: AssistantAvatar(
                                role: _role ?? widget.profile.role, size: 96),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Material(
                            color: BingoPalette.blue,
                            shape: const CircleBorder(
                                side:
                                    BorderSide(color: Colors.white, width: 3)),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => showCenterToast(context, '敬请期待'),
                              child: const Padding(
                                padding: EdgeInsets.all(9),
                                child: Icon(Icons.camera_alt_outlined,
                                    color: Colors.white, size: 19),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '让 Bingo 更懂你',
            style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: BingoPalette.ink),
          ),
          const SizedBox(height: 6),
          const Text(
            '设置可以随时修改，帮你打造更贴心的陪伴体验',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, color: Color(0xFF7E8A96), height: 1.4),
          ),
        ],
      );
}

class _SoftCircle extends StatelessWidget {
  const _SoftCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFE8F9F3).withValues(alpha: 0.62),
        ),
      );
}

class _AssistantNameIcon extends StatelessWidget {
  const _AssistantNameIcon();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 30,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                color: BingoPalette.blue, size: 29),
            Positioned(
              top: 11,
              child: Row(
                children: [
                  _IconDot(),
                  SizedBox(width: 3),
                  _IconDot(),
                  SizedBox(width: 3),
                  _IconDot(),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RoleIcon extends StatelessWidget {
  const _RoleIcon();

  static const _iconColor = Color(0xFF00B58A);

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 34,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              left: 1,
              top: 1,
              child: SizedBox.square(
                dimension: 29,
                child: CustomPaint(painter: _PersonOutlinePainter()),
              ),
            ),
            const Positioned(
              right: 0,
              bottom: 1,
              child: Icon(Icons.favorite_rounded, color: _iconColor, size: 15),
            ),
          ],
        ),
      );
}

class _PersonOutlinePainter extends CustomPainter {
  const _PersonOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _RoleIcon._iconColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(const Offset(12.5, 7), 4.7, paint);
    final shoulders = Path()
      ..moveTo(3.5, 27)
      ..cubicTo(3.8, 19.5, 7, 16.7, 12.5, 16.7)
      ..cubicTo(18, 16.7, 21.2, 19.5, 21.5, 27)
      ..lineTo(3.5, 27);
    canvas.drawPath(shoulders, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PersonalityIcon extends StatelessWidget {
  const _PersonalityIcon();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 32,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              bottom: 0,
              child: Icon(Icons.sentiment_satisfied_alt_rounded,
                  color: BingoPalette.blue, size: 29),
            ),
            Positioned(
              right: -2,
              top: -2,
              child: Icon(Icons.auto_awesome_rounded,
                  color: BingoPalette.blue, size: 14),
            ),
          ],
        ),
      );
}

class _IconDot extends StatelessWidget {
  const _IconDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          color: BingoPalette.blue,
          shape: BoxShape.circle,
        ),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.icon,
    required this.child,
    this.iconBackgroundColor = BingoPalette.softSurface,
  });

  final Widget icon;
  final Widget child;
  final Color iconBackgroundColor;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BingoPalette.line),
          boxShadow: [
            BoxShadow(
              color: BingoPalette.blue.withValues(alpha: 0.035),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBackgroundColor,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(child: icon),
            ),
            const SizedBox(width: 13),
            Expanded(child: child),
          ],
        ),
      );
}

class _ProfileTextCard extends StatelessWidget {
  const _ProfileTextCard({
    required this.label,
    required this.icon,
    required this.controller,
    required this.validator,
    required this.textInputAction,
  });

  final String label;
  final Widget icon;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) => _ProfileCard(
        icon: icon,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7E8A96),
                    fontWeight: FontWeight.w500)),
            TextFormField(
              controller: controller,
              validator: validator,
              textInputAction: textInputAction,
              maxLength: 31,
              buildCounter: (_,
                      {required currentLength,
                      required isFocused,
                      maxLength}) =>
                  null,
              style: const TextStyle(fontSize: 17, color: BingoPalette.ink),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.only(top: 5, bottom: 1),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
            ),
          ],
        ),
      );
}

class _ProfileDropdown extends StatefulWidget {
  const _ProfileDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onSelected,
    this.iconBackgroundColor = BingoPalette.softSurface,
    super.key,
  });

  final String label;
  final Widget icon;
  final Color iconBackgroundColor;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  State<_ProfileDropdown> createState() => _ProfileDropdownState();
}

class _ProfileDropdownState extends State<_ProfileDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => _ProfileCard(
        icon: widget.icon,
        iconBackgroundColor: widget.iconBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              expanded: _expanded,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.label,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF7E8A96),
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 5),
                          Text(widget.value ?? '请选择',
                              style: const TextStyle(
                                  fontSize: 17, color: BingoPalette.ink)),
                        ],
                      ),
                    ),
                    Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: const Color(0xFF788390)),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: BingoPalette.line),
              const SizedBox(height: 5),
              for (final option in widget.options)
                InkWell(
                  onTap: () {
                    setState(() => _expanded = false);
                    widget.onSelected(option);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(option,
                              style: TextStyle(
                                fontSize: 15,
                                color: option == widget.value
                                    ? BingoPalette.blue
                                    : BingoPalette.ink,
                                fontWeight: option == widget.value
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              )),
                        ),
                        if (option == widget.value)
                          const Icon(Icons.check_rounded,
                              color: BingoPalette.blue, size: 19),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
}
