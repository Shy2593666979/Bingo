import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bingo/features/auth/presentation/legal_document_data.dart';

class UserAgreementPage extends StatefulWidget {
  const UserAgreementPage({this.privacy = false, super.key});
  final bool privacy;

  @override
  State<UserAgreementPage> createState() => _UserAgreementPageState();
}

class _UserAgreementPageState extends State<UserAgreementPage> {
  static const _device = MethodChannel('bingo/device_tools');
  static const _repository = 'https://github.com/Shy2593666979/Bingo';
  late final _sections =
      (widget.privacy ? privacyPolicySections : userAgreementSections)
          .map((section) => (
                section.title,
                section.paragraphs.first,
                section.paragraphs.skip(1).join('\n\n')
              ))
          .toList();
  late final _sectionKeys = List.generate(_sections.length, (_) => GlobalKey());

  Future<void> _openRepository() async {
    try {
      await _device.invokeMethod<void>('openProjectRepository');
    } on Exception {
      await Clipboard.setData(const ClipboardData(text: _repository));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开浏览器，仓库链接已复制')));
    }
  }

  Widget _paragraph(String text) => Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Text(text,
          style: const TextStyle(
              fontSize: 14, height: 1.9, color: Color(0xFF63766E))));

  Widget _privacySection(int index) {
    final paragraphs = privacyPolicySections[index].paragraphs;
    if (index == 2) {
      final providers = <(String, List<String>)>[];
      for (final paragraph in paragraphs.skip(2)) {
        if (paragraph.contains(' · ')) {
          providers.add((paragraph, <String>[]));
        } else {
          providers.last.$2.add(paragraph);
        }
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final paragraph in paragraphs.take(2)) _paragraph(paragraph),
        for (final provider in providers)
          Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE1ECE5)),
                borderRadius: BorderRadius.circular(14)),
            child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                initiallyExpanded: provider.$1.startsWith('Yukisbox'),
                title: Text(provider.$1,
                    style: const TextStyle(
                        fontSize: 13, height: 1.6, color: Color(0xFF368D77))),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  for (final paragraph in provider.$2) _paragraph(paragraph)
                ]),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final paragraph in paragraphs) _paragraph(paragraph),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xFFFBFDFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFBFDFB),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(widget.privacy ? '隐私政策' : '用户协议',
            style: const TextStyle(fontSize: 18)),
      ),
      body: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 25),
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE6F5ED), Color(0xFFF7FBF7)])),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.asset('assets/images/bingo_logo.png',
                        width: 55, height: 55)),
                const SizedBox(width: 13),
                const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bingo',
                          style: TextStyle(
                              fontSize: 23, fontWeight: FontWeight.w700)),
                      SizedBox(height: 5),
                      Text('在这里，慢慢聊～',
                          style:
                              TextStyle(fontSize: 12, color: Color(0xFF7C918A)))
                    ])
              ]),
              const SizedBox(height: 25),
              Text(widget.privacy ? '把隐私，说清楚' : '遇见之前的小约定',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(
                  widget.privacy
                      ? '哪些信息会被使用，为什么需要它们，\n以及你可以如何管理自己的资料。'
                      : '感谢你来到 Bingo。开始陪伴之前，\n请花一点时间了解我们的服务与使用边界。',
                  style: const TextStyle(
                      fontSize: 13, height: 1.9, color: Color(0xFF6D857C))),
            ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(spacing: 16, runSpacing: 4, children: [
                    for (var index = 0; index < _sections.length; index++)
                      TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF368D77),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3)),
                          onPressed: () => Scrollable.ensureVisible(
                              _sectionKeys[index].currentContext!,
                              duration: const Duration(milliseconds: 280)),
                          child: Text(
                              '${(index + 1).toString().padLeft(2, '0')}  ${_sections[index].$1}',
                              style: const TextStyle(fontSize: 12)))
                  ]),
                  const SizedBox(height: 15),
                  for (var index = 0; index < _sections.length; index++)
                    Padding(
                        key: _sectionKeys[index],
                        padding: const EdgeInsets.only(bottom: 27),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFE9F3ED),
                                        borderRadius: BorderRadius.circular(9)),
                                    child: Text(
                                        (index + 1).toString().padLeft(2, '0'),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF368D77)))),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(_sections[index].$1,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)))
                              ]),
                              if (widget.privacy)
                                _privacySection(index)
                              else ...[
                                _paragraph(_sections[index].$2),
                                _paragraph(_sections[index].$3),
                              ],
                              if (!widget.privacy && index == 5)
                                TextButton(
                                    onPressed: () => Navigator.of(context)
                                        .push<void>(MaterialPageRoute(
                                            builder: (_) =>
                                                const PrivacyPolicyPage())),
                                    child: const Text('查看隐私政策'))
                            ])),
                  Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFFF0F7F2), Colors.white]),
                          border: Border.all(color: const Color(0xFFE1ECE5)),
                          borderRadius: BorderRadius.circular(18)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFDFF0E6),
                                      borderRadius: BorderRadius.circular(12)),
                                  child: const Icon(Icons.code_rounded,
                                      color: Color(0xFF368D77), size: 22)),
                              const SizedBox(width: 11),
                              const Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('项目创作者',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF7C918A))),
                                    SizedBox(height: 4),
                                    Text('田明广',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)),
                                    SizedBox(height: 2),
                                    Text('Mingguang.Tian',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF63766E)))
                                  ]))
                            ]),
                            _paragraph(
                                '把陪伴变成一个名字、一种性格、一个熟悉的声音。感谢每一个愿意体验和提出建议的人。'),
                            const SizedBox(height: 12),
                            const Divider(color: BingoPalette.line),
                            TextButton.icon(
                                onPressed: () => openPrivacyEmail(context),
                                icon: const Icon(Icons.mail_outline_rounded,
                                    size: 18),
                                label: const Text('bingo202610@126.com',
                                    style: TextStyle(fontSize: 12))),
                            InkWell(
                                onTap: _openRepository,
                                borderRadius: BorderRadius.circular(10),
                                child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Row(children: [
                                      Icon(Icons.code_rounded,
                                          size: 20, color: Color(0xFF368D77)),
                                      SizedBox(width: 9),
                                      Expanded(
                                          child: Text('Shy2593666979 / Bingo',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF368D77)))),
                                      Icon(Icons.open_in_new_rounded,
                                          size: 15, color: Color(0xFF368D77))
                                    ])))
                          ])),
                  const SizedBox(height: 24),
                  const Text('认真对待你的每一次表达。\nBingo · 在这里，慢慢聊',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, height: 1.8, color: Color(0xFF93A59B)))
                ]))
      ])),
      bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: BingoPalette.line))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD5EEE0),
                            foregroundColor: const Color(0xFF347B63),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16))),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('我已了解，返回')))
              ]))));
}

class PrivacyPolicyPage extends UserAgreementPage {
  const PrivacyPolicyPage({super.key}) : super(privacy: true);
}

Future<void> openPrivacyEmail(BuildContext context,
    {bool deletion = false}) async {
  try {
    await const MethodChannel('bingo/device_tools')
        .invokeMethod<void>('openPrivacyEmail', {'deletion': deletion});
  } on Exception {
    await Clipboard.setData(const ClipboardData(text: 'bingo202610@126.com'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开邮件应用，邮箱已复制：bingo202610@126.com')));
  }
}
