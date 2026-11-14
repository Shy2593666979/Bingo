import 'package:bingo/core/design/approved_art.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/design/companion_launch_ui.dart';
import 'package:bingo/core/design/reference_design.dart';
import 'package:flutter/material.dart';

class CreateChoiceDialog extends StatelessWidget {
  const CreateChoiceDialog({super.key});
  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('创建搭子',
                      style: CompanionLaunch.text(18, weight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Text('选择创建方式',
                      style: CompanionLaunch.text(14,
                          color: const Color(0xFF777777))),
                  const SizedBox(height: 22),
                  _choice(context, 'role', Icons.auto_fix_high_rounded, '创建搭子',
                      '从头像、设定和背景开始创建'),
                  _choice(context, 'group', Icons.group_add_outlined, '创建群聊',
                      '选择几位搭子，创建属于你们的群聊'),
                  const SizedBox(height: 18),
                  SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 46),
                              side:
                                  const BorderSide(color: BingoPalette.primary),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20))),
                          child: const Text('取消'))),
                ]))),
      );
  Widget _choice(BuildContext context, String action, IconData icon,
          String title, String text) =>
      InkWell(
          onTap: () => Navigator.pop(context, action),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(children: [
                Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: BingoPalette.softSurface),
                    child: Icon(icon, size: 23, color: BingoPalette.ink)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: CompanionLaunch.text(15,
                              weight: FontWeight.w600)),
                      const SizedBox(height: 7),
                      Text(text,
                          style: CompanionLaunch.text(14,
                              color: const Color(0xFF999999))),
                    ])),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: Color(0xFF999999)),
              ])));
}

class CreateCenterPage extends StatelessWidget {
  const CreateCenterPage(
      {required this.onCreateRole,
      required this.onCreateGroup,
      required this.onPublish,
      this.onDestination,
      this.onManageRoles,
      this.onVoices,
      super.key});
  final Future<void> Function() onCreateRole, onCreateGroup, onPublish;
  final VoidCallback? onManageRoles, onVoices;
  final ValueChanged<int>? onDestination;
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.white,
      appBar: onDestination == null
          ? AppBar(title: const Text('创建'), centerTitle: true)
          : null,
      bottomNavigationBar: onDestination == null
          ? null
          : ReferenceNavigation(
              selected: -1,
              creating: true,
              onSelected: onDestination!,
              onCreate: () {}),
      body: SafeArea(
          top: onDestination != null,
          bottom: false,
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (onDestination != null)
                  const SizedBox(
                      height: 64,
                      child: Center(
                          child: Text('创建',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w600)))),
                const SizedBox(height: 48),
                _entry(Icons.person_add_alt_1_outlined, '创建搭子', '认识一个新的陪伴',
                    onCreateRole),
                const SizedBox(height: 23),
                _entry(
                    Icons.groups_outlined, '创建群聊', '把喜欢的搭子聚在一起', onCreateGroup),
                const SizedBox(height: 61),
                const Divider(),
                ListTile(
                    onTap: onManageRoles,
                    leading: const Icon(Icons.person_outline_rounded),
                    title: const Text('我的搭子',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right_rounded)),
                const Divider(),
                ListTile(
                    onTap: onVoices,
                    leading: const Icon(Icons.graphic_eq_rounded),
                    title: const Text('我的音色',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right_rounded)),
                const Divider(),
              ])));
  Widget _entry(
          IconData icon, String title, String subtitle, VoidCallback action) =>
      Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: BingoPalette.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: action,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 105),
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(children: [
                        ApprovedCreateIcon(group: title == '创建群聊'),
                        const SizedBox(width: 20),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(title,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 5),
                              Text(subtitle,
                                  style: const TextStyle(
                                      fontSize: 14, color: BingoPalette.muted))
                            ])),
                        const Icon(Icons.chevron_right_rounded,
                            size: 18, color: BingoPalette.muted)
                      ])))));
}
