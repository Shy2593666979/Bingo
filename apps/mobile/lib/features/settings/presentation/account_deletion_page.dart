import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/material.dart';

import 'package:bingo/features/settings/presentation/account_deletion_icon.dart';

class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage(
      {required this.gateway, required this.onDeleted, super.key});
  final AccountDeletionGateway gateway;
  final Future<void> Function() onDeleted;

  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  bool _acknowledged = false;
  bool _deleting = false;
  String? _error;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('确认注销账号？'),
                content: const Text('账号、对话与自定义伙伴将被删除，注销后无法恢复。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('暂不注销')),
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('确认注销',
                          style: TextStyle(color: Color(0xFFBE7870)))),
                ]));
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.gateway.deleteAccount();
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = error is ApiException ? error.message : '注销失败，请稍后重试';
        });
      }
      return;
    }
    await widget.onDeleted();
  }

  static const _impacts = [
    (Icons.person_outline_rounded, '账号与个人资料', '注销后无法继续登录，昵称、生日、头像与登录会话将被删除。'),
    (
      Icons.chat_bubble_outline_rounded,
      '对话与长期记忆',
      '账号下的聊天、图片、位置消息及长期记忆将被删除，不再用于后续陪伴。'
    ),
    (Icons.graphic_eq_rounded, '伙伴与声音', '自定义伙伴将被删除，复刻音色停止使用，并提交声音服务清理。'),
    (
      Icons.favorite_border_rounded,
      '陪伴记录与提醒',
      '本机的小记、约定与聊天缓存将被清理。手机系统中已创建的闹钟，请在系统闹钟中自行管理。'
    ),
  ];

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_deleting,
      child: Scaffold(
        backgroundColor: const Color(0xFFFBFDFB),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFBFDFB),
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('注销账号', style: TextStyle(fontSize: 18)),
        ),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Center(
              child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: const Color(0xFFF8ECE8),
                borderRadius: BorderRadius.circular(24)),
            child: const Center(child: AccountDeletionIcon(size: 34)),
          )),
          const SizedBox(height: 22),
          const Text('准备和 Bingo 告别吗？',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('这不是退出登录。注销处理完成后，原账号与相关内容将无法继续使用或恢复。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, height: 1.8, color: Color(0xFF75827C))),
          const SizedBox(height: 24),
          for (final impact in _impacts)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE5EDE7)),
                  borderRadius: BorderRadius.circular(18)),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(impact.$1, size: 22, color: const Color(0xFF78A68F)),
                const SizedBox(width: 13),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(impact.$2,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 7),
                      Text(impact.$3,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.8,
                              color: Color(0xFF75827C))),
                    ])),
              ]),
            ),
          const SizedBox(height: 8),
          const Text('确认后将直接注销当前登录的账号，此操作无法撤销。',
              style: TextStyle(
                  fontSize: 13, height: 1.8, color: Color(0xFF75827C))),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _acknowledged,
              onChanged: _deleting
                  ? null
                  : (value) => setState(() => _acknowledged = value ?? false),
              title: const Text('我已了解注销后的影响', style: TextStyle(fontSize: 13))),
        ]),
        bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFF0D9D3),
                            foregroundColor: const Color(0xFFA6645C),
                            padding: const EdgeInsets.symmetric(vertical: 15)),
                        onPressed: _acknowledged && !_deleting ? _delete : null,
                        child: _deleting
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('注销账号'))),
                TextButton(
                    onPressed:
                        _deleting ? null : () => Navigator.of(context).pop(),
                    child: const Text('保留账号，返回')),
              ]),
            )),
      ));
}
