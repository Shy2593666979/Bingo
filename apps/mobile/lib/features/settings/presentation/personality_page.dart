import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';

class PersonalityPage extends StatefulWidget {
  const PersonalityPage(
      {required this.options, required this.save, this.selected, super.key});
  final List<String> options;
  final String? selected;
  final Future<UserProfile> Function(String) save;

  @override
  State<PersonalityPage> createState() => _PersonalityPageState();
}

class _PersonalityPageState extends State<PersonalityPage> {
  static const _descriptions = {
    '温柔体贴': '先听你说完，再给你一点温暖和支持。',
    '理性严谨': '认真梳理问题，用清晰、有依据的建议帮助你。',
    '幽默风趣': '用轻松有趣的表达，让日常聊天多一点笑意。',
    '尖酸刻薄': '表达直接，偶尔犀利吐槽，但尊重你的感受。',
    '积极活泼': '带着热情和好奇心，陪你发现生活里的小快乐。',
    '沉稳克制': '不急着下结论，用平和、稳重的回应陪你思考。',
  };
  String? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.options.contains(widget.selected)
        ? widget.selected
        : widget.options.firstOrNull;
  }

  Future<void> _save() async {
    if (_busy || _selected == null) return;
    setState(() => _busy = true);
    try {
      final profile = await widget.save(_selected!);
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pop(context, profile);
    } on Exception catch (error) {
      if (mounted) {
        showCenterToast(
            context, error is ApiException ? error.message : '暂时无法更新性格，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: buildMintTheme(context),
      child: PopScope(
          canPop: !_busy,
          child: Scaffold(
            appBar: AppBar(title: const Text('聊天性格'), centerTitle: true),
            body: ListView(padding: const EdgeInsets.all(24), children: [
              const SizedBox(height: 18),
              const Text('你喜欢怎样的回应？',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text('这是默认性格。每位伙伴也可以拥有自己的性格。',
                  style: TextStyle(color: Color(0xFF7D918A), height: 1.7)),
              const SizedBox(height: 24),
              Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24)),
                  child: Wrap(spacing: 9, runSpacing: 10, children: [
                    for (final option in widget.options)
                      ChoiceChip(
                          label: Text(option),
                          showCheckmark: false,
                          selected: option == _selected,
                          selectedColor: BingoPalette.mintTint,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                              color: option == _selected
                                  ? BingoPalette.mintPrimary
                                  : BingoPalette.ink),
                          side: const BorderSide(color: BingoPalette.line),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _selected = option)),
                  ])),
              const SizedBox(height: 16),
              Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selected ?? '暂无可选性格',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Text(_descriptions[_selected] ?? '选择你喜欢的回应方式。',
                            style: const TextStyle(
                                color: Color(0xFF7D918A), height: 1.8)),
                        const Text('不同角色依然保留自己的身份与表达方式。',
                            style: TextStyle(
                                color: Color(0xFF7D918A), height: 1.8)),
                      ])),
            ]),
            bottomNavigationBar: SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: FilledButton(
                        onPressed: _busy || _selected == null ? null : _save,
                        child: Text(_busy ? '正在保存…' : '保存性格')))),
          )));
}
