import 'package:bingo/core/design/companion_launch_ui.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';

class CompanionLibraryPage extends StatefulWidget {
  const CompanionLibraryPage(
      {required this.gateway,
      required this.onRole,
      required this.onCreate,
      super.key});
  final RoleGateway gateway;
  final Future<void> Function(String) onRole;
  final Future<void> Function() onCreate;
  @override
  State<CompanionLibraryPage> createState() => _CompanionLibraryPageState();
}

class _CompanionLibraryPageState extends State<CompanionLibraryPage> {
  List<RoleOption>? _roles;
  String? _error;
  String _query = '';
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final roles = await widget.gateway.listRoles();
      if (mounted) {
        setState(() {
          _roles = roles;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '搭子列表加载失败，请重试');
    }
  }

  List<RoleOption> get _visible => (_roles ?? [])
      .where((role) =>
          (_tab == 0 || role.identityEditable) &&
          '${role.displayName} ${role.typeLabel} ${role.description}'
              .toLowerCase()
              .contains(_query.toLowerCase()))
      .toList();
  Future<void> _open(RoleOption role) async {
    await widget.onRole(role.id);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('我的搭子'), centerTitle: true, actions: [
        IconButton(
            tooltip: '创建搭子',
            icon: const Icon(Icons.add_rounded),
            onPressed: () async {
              await widget.onCreate();
              if (mounted) await _load();
            })
      ]),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                TextField(
                    onChanged: (value) => setState(() => _query = value.trim()),
                    style: CompanionLaunch.text(15),
                    decoration: InputDecoration(
                        hintText: '查找搭子',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFF0F0F0))))),
                const SizedBox(height: 18),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final item in [(0, '全部搭子'), (1, '我创建的')])
                    ChoiceChip(
                        label: Text(item.$2),
                        selected: _tab == item.$1,
                        showCheckmark: false,
                        selectedColor: BingoPalette.primary,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFF0F0F0)),
                        labelStyle: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _tab == item.$1
                                ? Colors.white
                                : const Color(0xFF222222)),
                        shape: const StadiumBorder(),
                        onSelected: (_) => setState(() => _tab = item.$1)),
                ]),
                if (_error != null)
                  TextButton(onPressed: _load, child: Text(_error!)),
                if (_roles == null && _error == null)
                  const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator())),
                if (_roles != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('共 ${_visible.length} 位搭子',
                          style: CompanionLaunch.text(14,
                              color: CompanionLaunch.muted))),
                if (_roles != null && _visible.isEmpty)
                  Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text('还没有符合条件的搭子。',
                          style: CompanionLaunch.text(14,
                              color: CompanionLaunch.muted))),
                for (final role in _visible) _card(role),
              ])));

  Widget _card(RoleOption role) => Padding(
      key: ValueKey('library-role-${role.id}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F1F1)),
              boxShadow: const []),
          child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                  onTap: () => _open(role),
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox.square(
                                      dimension: 56,
                                      child: AssistantAvatar(
                                          role: role.name,
                                          size: 56,
                                          showOnline: true)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(role.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: CompanionLaunch.text(16,
                                                weight: FontWeight.w500)),
                                        const SizedBox(height: 7),
                                        Text(
                                            role.description.isEmpty
                                                ? role.typeLabel
                                                : role.description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: CompanionLaunch.text(14,
                                                color: const Color(0xFF666666),
                                                height: 1.4)),
                                      ])),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.chevron_right_rounded,
                                      size: 20, color: Color(0xFFAAAAAA)),
                                ]),
                            if (role.personalityTags.isNotEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final tag
                                            in role.personalityTags.take(3))
                                          Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFF6F6F6),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20)),
                                              child: Text('#$tag',
                                                  style: CompanionLaunch.text(
                                                      12,
                                                      color: const Color(
                                                          0xFF666666)))),
                                      ])),
                          ]))))));
}
