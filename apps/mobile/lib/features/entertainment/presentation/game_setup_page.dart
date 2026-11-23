import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/presentation/game_widgets.dart';
import 'package:bingo/features/entertainment/presentation/party_table.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:flutter/material.dart';

class GameSetupPage extends StatefulWidget {
  const GameSetupPage(
      {required this.game,
      required this.people,
      required this.groups,
      required this.profile,
      required this.onCreateRole,
      this.groupsFailed = false,
      super.key});
  final CompanionGame game;
  final List<GameCompanion> people;
  final List<ChatGroup> groups;
  final UserProfile profile;
  final VoidCallback onCreateRole;
  final bool groupsFailed;
  @override
  State<GameSetupPage> createState() => _GameSetupPageState();
}

class _GameSetupPageState extends State<GameSetupPage> {
  int _step = 0, _rounds = 5, _seats = 7;
  bool _fromGroup = false;
  ChatGroup? _group;
  String _mood = '朋友派对';
  String? _identity;
  final _selected = <String>{};
  int get _max => widget.game == CompanionGame.truth ? 5 : _seats - 1;
  String get _username => widget.profile.username?.trim().isNotEmpty == true
      ? widget.profile.username!
      : '我';
  List<GameCompanion> get _available => _fromGroup
      ? _group?.activeMembers.map(GameCompanion.fromMember).toList() ?? []
      : widget.people;
  List<GameCompanion> get _chosen =>
      _available.where((p) => _selected.contains(p.id)).toList();
  GameSetup get _draft => GameSetup(
      game: widget.game,
      companions: _chosen,
      groupId: _fromGroup ? _group?.id : null,
      groupName: _fromGroup ? _group?.name : null,
      rounds: _rounds,
      wolfSeats: _seats,
      identity: _identity,
      mood: _mood);
  @override
  void initState() {
    super.initState();
    _group = widget.groups.firstOrNull;
  }

  void _selectSource(bool value) => setState(() {
        _fromGroup = value;
        _selected.clear();
      });
  void _toggle(GameCompanion p) => setState(() {
        if (_selected.contains(p.id)) {
          _selected.remove(p.id);
        } else if (_selected.length < _max) {
          _selected.add(p.id);
        }
      });
  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
              backgroundColor: Colors.white,
              centerTitle: true,
              actions: [
                if (_step == 0)
                  IconButton(
                      tooltip: '玩法配置',
                      onPressed: () => setState(() => _step = 1),
                      icon: const Icon(Icons.tune_rounded,
                          size: 21, color: gameRose))
              ],
              leading: IconButton(
                  onPressed: _back,
                  icon: const Icon(Icons.chevron_left, color: gameInk)),
              title: _step == 0
                  ? null
                  : Text(widget.game.title,
                      style: const TextStyle(
                          fontSize: 17,
                          color: gameInk,
                          fontWeight: FontWeight.w600))),
          body: Column(children: [
            if (_step > 0)
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 35, vertical: 17),
                  child: Row(children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0)
                        Expanded(
                            child: Container(
                                height: 1,
                                color: i <= _step ? gameRose : gameLine)),
                      Column(children: [
                        Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i <= _step
                                    ? gameRose
                                    : const Color(0xFFF0E6ED)),
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: i <= _step
                                        ? Colors.white
                                        : gameMuted))),
                        const SizedBox(height: 7),
                        Text(['邀请谁', '选玩法', '准备开场'][i],
                            style: TextStyle(
                                fontSize: 11,
                                color: i == _step ? gameRose : gameMuted))
                      ])
                    ]
                  ])),
            Expanded(
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    children: _step == 0
                        ? _pick()
                        : _step == 1
                            ? _configure()
                            : _confirm())),
            SafeArea(
                top: false,
                child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
                    decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: gameLine))),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (_step == 0) _selectionSummary(),
                      if (_draft.validationError != null)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Text(_draft.validationError!,
                                style: const TextStyle(
                                    color: gameMuted, fontSize: 12))),
                      GameButton(
                          _step == 0
                              ? '开始小聚 ›'
                              : _step == 2
                                  ? '开始体验小聚'
                                  : '下一步',
                          onPressed: _draft.validationError != null
                              ? null
                              : () {
                                  if (_step == 1) {
                                    setState(() => _step++);
                                  } else {
                                    Navigator.pop(context, _draft);
                                  }
                                }),
                    ]))),
          ])));

  List<Widget> _pick() => [
        const Stack(alignment: Alignment.center, children: [
          Text('邀请谁一起玩',
              style: TextStyle(
                  fontSize: 23,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: gameInk)),
          Positioned(right: 48, top: 0, child: GameAccent()),
        ]),
        const SizedBox(height: 7),
        const Center(
            child: Text('选几位搭子，来一场轻松的小聚吧',
                style: TextStyle(
                    fontSize: 15, height: 1.5, color: Color(0xFF6D666C)))),
        const SizedBox(height: 26),
        Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
                color: const Color(0xFFF8F5F7),
                border: Border.all(color: const Color(0xFFE9E0E5)),
                borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              for (final from in [true, false])
                Expanded(
                    child: InkWell(
                        onTap: () => _selectSource(from),
                        borderRadius: BorderRadius.circular(13),
                        child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                                color: _fromGroup == from
                                    ? gameRose
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(13)),
                            child: Text(from ? '已有群聊' : '我的搭子',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: _fromGroup == from
                                        ? Colors.white
                                        : gameInk)))))
            ])),
        const SizedBox(height: 19),
        if (widget.game == CompanionGame.wolf) ...[
          _seatChoices(),
          const SizedBox(height: 16)
        ],
        if (_fromGroup) ...[
          if (widget.groupsFailed)
            const Text('群聊暂时没读到，可返回娱乐页下拉重试，或从我的搭子组局。',
                style: TextStyle(color: gameMuted, height: 1.8)),
          if (widget.groups.isEmpty && !widget.groupsFailed)
            const Text('还没有群聊，可以切到「选搭子组新群」。',
                style: TextStyle(color: gameMuted, height: 1.8)),
          for (final g in widget.groups)
            Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => setState(() {
                              _group = g;
                              _selected.clear();
                            }),
                        child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: _group?.id == g.id
                                    ? const Color(0xFFFFEFF7)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: _group?.id == g.id
                                        ? gameRose
                                        : gameLine)),
                            child: Row(children: [
                              SizedBox(
                                  width: 55,
                                  child: Wrap(
                                      spacing: 3,
                                      runSpacing: 3,
                                      children: g.activeMembers
                                          .take(4)
                                          .map((p) => GamePortrait(
                                              GameCompanion.fromMember(p),
                                              size: 24))
                                          .toList())),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(g.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: gameInk)),
                                    const SizedBox(height: 5),
                                    Text('${g.activeMembers.length} 位搭子',
                                        style: const TextStyle(
                                            fontSize: 12, color: gameMuted))
                                  ])),
                              Icon(
                                  _group?.id == g.id
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 20,
                                  color:
                                      _group?.id == g.id ? gameRose : gameMuted)
                            ]))))),
          const SizedBox(height: 11),
        ],
        const SizedBox(height: 12),
        if (_available.isEmpty && !_fromGroup)
          TextButton.icon(
              onPressed: widget.onCreateRole,
              icon: const Icon(Icons.add),
              label: const Text('先创建我的搭子')),
        LayoutBuilder(
            builder: (context, constraints) => Wrap(
                spacing: 14,
                runSpacing: 14,
                children: _available.map((p) {
                  final selected = _selected.contains(p.id);
                  final disabled = !selected && _selected.length >= _max;
                  const columns = 2;
                  return SizedBox(
                      width:
                          (constraints.maxWidth - 14 * (columns - 1)) / columns,
                      child: Semantics(
                          button: true,
                          selected: selected,
                          label: p.name,
                          child: InkWell(
                              onTap: disabled ? null : () => _toggle(p),
                              borderRadius: BorderRadius.circular(15),
                              child: Opacity(
                                  opacity: disabled ? .5 : 1,
                                  child: Container(
                                      padding:
                                          const EdgeInsets.fromLTRB(6, 8, 6, 8),
                                      decoration: BoxDecoration(
                                          color: selected
                                              ? const Color(0xFFFFF5F9)
                                              : const Color(0xFFFBF8FA),
                                          borderRadius:
                                              BorderRadius.circular(15),
                                          border: Border.all(
                                              color: selected
                                                  ? gameRose
                                                  : gameLine)),
                                      child: Column(children: [
                                        Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              GamePortrait(p,
                                                  size: (constraints.maxWidth -
                                                              14) /
                                                          2 -
                                                      61),
                                              Positioned(
                                                  top: -1,
                                                  right: -18,
                                                  child: Container(
                                                      width: 24,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                          color: selected
                                                              ? gameRose
                                                              : Colors.white,
                                                          shape:
                                                              BoxShape.circle,
                                                          border: Border.all(
                                                              color: selected
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFFAAA4AA),
                                                              width: 1.5)),
                                                      child: selected
                                                          ? const Icon(
                                                              Icons.check,
                                                              size: 17,
                                                              color:
                                                                  Colors.white)
                                                          : null))
                                            ]),
                                        const SizedBox(height: 7),
                                        Text(p.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                height: 1.4,
                                                color: gameInk))
                                      ]))))));
                }).toList())),
      ];

  Widget _selectionSummary() => Padding(
      padding: const EdgeInsets.only(bottom: 38),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('已选择 ${_chosen.length} 人',
              style: const TextStyle(fontSize: 15, color: gameInk)),
          const Spacer(),
          TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('清空',
                  style: TextStyle(color: gameRose, fontSize: 13)))
        ]),
        const SizedBox(height: 4),
        Wrap(
            spacing: 10,
            runSpacing: 8,
            children: _chosen
                .map((p) => Container(
                    padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFBF1F6),
                        borderRadius: BorderRadius.circular(22)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      GamePortrait(p, size: 30),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 95),
                          child: Text(p.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: gameInk))),
                      const SizedBox(width: 4),
                      InkWell(
                          onTap: () => _toggle(p),
                          child: const Icon(Icons.close,
                              size: 16, color: gameMuted)),
                    ])))
                .toList()),
      ]));

  Widget _seatChoices() => SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 5, label: Text('5 人小局')),
            ButtonSegment(value: 7, label: Text('7 人标准局'))
          ],
          selected: {
            _seats
          },
          onSelectionChanged: (value) => setState(() {
                _seats = value.first;
                if (_seats == 5 && _identity == 'witch') _identity = null;
                while (_selected.length > _max) {
                  _selected.remove(_selected.last);
                }
              }));

  List<Widget> _configure() => [
        GameSectionTitle(
            widget.game == CompanionGame.truth ? '选好玩法，就出发。' : '今晚，谁藏着秘密？',
            subtitle: '玩法固定，聊天自由。每位搭子都是独立的参与者。'),
        if (widget.game == CompanionGame.truth) ...[
          const Text('游戏轮次',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: gameInk)),
          const SizedBox(height: 13),
          SegmentedButton<int>(
              segments: [
                for (final n in [3, 5, 8])
                  ButtonSegment(value: n, label: Text('$n 轮'))
              ],
              selected: {
                _rounds
              },
              onSelectionChanged: (value) =>
                  setState(() => _rounds = value.first)),
          const SizedBox(height: 27),
          const Text('派对氛围',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: gameInk)),
          const SizedBox(height: 13),
          RadioGroup<String>(
              groupValue: _mood,
              onChanged: (value) => setState(() => _mood = value!),
              child: Column(children: [
                for (final (label, note, icon) in [
                  ('朋友派对', '轻松有趣，慢慢增进了解', Icons.people_outline),
                  ('心动派对', '温柔一点，聊聊彼此的心事', Icons.favorite_outline),
                  ('世界观派对', '脑洞设定，试试有趣的假设', Icons.auto_awesome_outlined)
                ])
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RadioListTile<String>(
                          value: label,
                          activeColor: gameRose,
                          secondary: Icon(icon, color: gameRose),
                          title: Text(label,
                              style: const TextStyle(
                                  fontSize: 14, color: gameInk)),
                          subtitle: Text(note,
                              style: const TextStyle(
                                  fontSize: 12, color: gameMuted)),
                          shape: RoundedRectangleBorder(
                              side: BorderSide(
                                  color: _mood == label ? gameRose : gameLine),
                              borderRadius: BorderRadius.circular(16)))),
              ])),
          const SizedBox(height: 12),
          const Text('不想回答，可以随时换题或跳过。题目与挑战都应能在聊天中完成。',
              style: TextStyle(fontSize: 12, height: 1.8, color: gameMuted)),
        ] else ...[
          _seatChoices(),
          const SizedBox(height: 20),
          GameSurface(
              lilac: true,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.nights_stay_rounded,
                        color: gameLilac, size: 40),
                    const SizedBox(height: 12),
                    Text(
                        _seats == 7
                            ? '2 狼人 · 1 预言家 · 1 女巫 · 3 村民'
                            : '1 狼人 · 1 预言家 · 3 村民',
                        style: const TextStyle(
                            fontSize: 15, height: 1.8, color: gameInk)),
                    const SizedBox(height: 10),
                    const Text(
                        '白天一起讨论、正式投票；夜间身份行动仅自己可见。消灭全部狼人，好人获胜；狼人数量不少于好人时，狼人获胜。',
                        style: TextStyle(
                            fontSize: 12, height: 1.9, color: gameMuted))
                  ])),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
              key: ValueKey('identity-$_seats'),
              initialValue: _identity ?? 'random',
              decoration: const InputDecoration(labelText: '你的身份'),
              items: [
                const DropdownMenuItem(value: 'random', child: Text('随机身份')),
                const DropdownMenuItem(value: 'wolf', child: Text('狼人')),
                const DropdownMenuItem(value: 'seer', child: Text('预言家')),
                if (_seats == 7)
                  const DropdownMenuItem(value: 'witch', child: Text('女巫')),
                const DropdownMenuItem(value: 'villager', child: Text('村民')),
              ],
              onChanged: (value) =>
                  setState(() => _identity = value == 'random' ? null : value)),
          if (_draft.validationError != null) ...[
            const SizedBox(height: 15),
            TextButton(
                onPressed: () => setState(() => _step = 0),
                child: const Text('返回补选搭子'))
          ],
        ],
        const SizedBox(height: 25),
        const Text('本局玩家',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: gameInk)),
        const SizedBox(height: 16),
        GameRoster(
            people: _chosen,
            username: _username,
            userAvatarData: widget.profile.userAvatarData),
      ];

  List<Widget> _confirm() => [
        const GameSectionTitle('位置留好了，准备开场。', subtitle: '你只管参与，主持人会带着大家聊下去。'),
        GameSurface(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
                widget.game == CompanionGame.truth
                    ? Icons.favorite_rounded
                    : Icons.nights_stay_rounded,
                color: gameRose,
                size: 24),
            const SizedBox(width: 10),
            Expanded(
                child: Text(widget.game.title,
                    style: const TextStyle(
                        fontSize: 18,
                        color: gameInk,
                        fontWeight: FontWeight.w600)))
          ]),
          const SizedBox(height: 8),
          Text(
              widget.game == CompanionGame.truth
                  ? '$_mood · $_rounds 轮'
                  : '$_seats 人局 · 随机身份',
              style: const TextStyle(color: gameMuted, fontSize: 12)),
          const SizedBox(height: 16),
          PartyTable(
              caption: '这场，一起玩',
              people: _chosen,
              username: _username,
              userAvatarData: widget.profile.userAvatarData),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(color: gameLine)),
          _detail('游戏群聊', _draft.roomName),
          _detail('参与人数', '你和 ${_chosen.length} 位搭子'),
          _detail('预计时长', widget.game.duration),
        ])),
        const SizedBox(height: 17),
        const ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: 4),
            title:
                Text('玩法与隐私说明', style: TextStyle(fontSize: 14, color: gameInk)),
            children: [
              Padding(
                  padding: EdgeInsets.fromLTRB(6, 0, 6, 16),
                  child: Text('身份、查验等信息只对有权限的玩家可见。游戏中的发言与日常陪伴记忆分开，未经选择不保存共同回忆。',
                      style: TextStyle(
                          fontSize: 12, height: 1.9, color: gameMuted)))
            ]),
        const SizedBox(height: 14),
        const Text('开场有人接话，搭子依次参与。每轮结束会有提示；轮到你时等待你的回答。',
            style: TextStyle(fontSize: 12, height: 1.9, color: gameInk)),
        const SizedBox(height: 12),
        const Text('当前进入的是本地界面体验，不创建真实群聊、不调用 AI，也不会发送聊天消息。',
            style: TextStyle(fontSize: 12, height: 1.9, color: gameMuted)),
      ];
  Widget _detail(String title, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 12, color: gameMuted)),
        const SizedBox(width: 18),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style:
                    const TextStyle(fontSize: 12, height: 1.6, color: gameInk)))
      ]));
}
