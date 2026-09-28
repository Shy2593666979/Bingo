import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';

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
  String? _personality;
  String? _role;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.profile.username);
    _assistantNameController = TextEditingController(
      text: widget.profile.assistantName ?? 'Bingo',
    );
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final options = await widget.gateway.getProfileOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        _personality =
            widget.profile.personality ?? options.personalities.first;
        final savedRole = widget.profile.role;
        _role = savedRole != null && options.roles.contains(savedRole)
            ? savedRole
            : options.roles.first;
        _error = null;
      });
    } on Exception {
      if (mounted) setState(() => _error = '无法加载助手选项，请重试');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _personality == null ||
        _role == null ||
        _saving) {
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
        personality: _personality!,
        role: _role!,
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

  @override
  void dispose() {
    _usernameController.dispose();
    _assistantNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onCancel == null
            ? null
            : IconButton(
                onPressed: widget.onCancel,
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(widget.onCancel == null ? '设置你的助理' : '个性化设置'),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: BingoPalette.softGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.74),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14243B72),
                        blurRadius: 30,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: AssistantAvatar(role: _role, size: 88),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '让助理更符合你的习惯',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '你的用户名',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: _requiredName,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _assistantNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '助手名称',
                            prefixIcon: Icon(Icons.smart_toy_outlined),
                          ),
                          validator: _requiredName,
                        ),
                        const SizedBox(height: 14),
                        if (_options case final options?) ...[
                          _ProfileDropdown(
                            key: ValueKey('role-$_role'),
                            label: '助手角色',
                            icon: Icons.people_outline_rounded,
                            value: _role,
                            options: options.roles,
                            onSelected: (value) =>
                                setState(() => _role = value),
                          ),
                          const SizedBox(height: 14),
                          _ProfileDropdown(
                            key: ValueKey('personality-$_personality'),
                            label: '助手性格',
                            icon: Icons.psychology_outlined,
                            value: _personality,
                            options: options.personalities,
                            onSelected: (value) =>
                                setState(() => _personality = value),
                          ),
                        ] else
                          const Center(child: CircularProgressIndicator()),
                        if (_error case final error?) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(error,
                                    style: TextStyle(color: colors.error)),
                              ),
                              if (_options == null)
                                IconButton(
                                  onPressed: _loadOptions,
                                  tooltip: '重试',
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _options == null || _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_rounded),
                          label: const Text('保存并继续'),
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

  String? _requiredName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return '此项不能为空';
    if (name.length > 30) return '最多输入 30 个字符';
    return null;
  }
}

class _ProfileDropdown extends StatefulWidget {
  const _ProfileDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onSelected,
    super.key,
  });

  final String label;
  final IconData icon;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onSelected;

  @override
  State<_ProfileDropdown> createState() => _ProfileDropdownState();
}

class _ProfileDropdownState extends State<_ProfileDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: InputDecorator(
              isEmpty: value == null,
              decoration: InputDecoration(
                labelText: widget.label,
                prefixIcon: Icon(widget.icon),
                suffixIcon: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.94),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: BingoPalette.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: BingoPalette.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: BingoPalette.blue, width: 1.5),
                ),
              ),
              child: Text(value ?? '请选择'),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: !_expanded
              ? const SizedBox.shrink()
              : Container(
                  margin: const EdgeInsets.only(top: 6),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BingoPalette.line),
                  ),
                  child: Column(
                    children: [
                      for (var index = 0;
                          index < widget.options.length;
                          index++) ...[
                        _ProfileDropdownOption(
                          label: widget.options[index],
                          selected: widget.options[index] == value,
                          onTap: () {
                            final selected = widget.options[index];
                            setState(() => _expanded = false);
                            widget.onSelected(selected);
                          },
                        ),
                        if (index < widget.options.length - 1)
                          const Divider(height: 1, color: BingoPalette.line),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProfileDropdownOption extends StatelessWidget {
  const _ProfileDropdownOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? BingoPalette.blue.withValues(alpha: 0.09)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: BingoPalette.blue,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
