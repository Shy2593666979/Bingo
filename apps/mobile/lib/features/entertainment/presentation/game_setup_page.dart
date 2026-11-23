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
          backgroundColor: const Color(0xFFFAF7F9),
          appBar: AppBar(
              backgroundColor: const Color(0xFFFAF7F9),
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              actions: [
                if (_step == 0)
                  Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: TextButton.icon(
                          style: TextButton.styleFrom(
                              foregroundColor: gameRose,
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              minimumSize: const Size(0, 32),
                              side: const BorderSide(color: Color(0xFFF1E6EC)),
                              shape: const StadiumBorder()),
                          onPressed: () => setState(() => _step = 1),
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('设置',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600))))
              ],
              leading: IconButton(
                  onPressed: _back,
                  icon: const Icon(Icons.chevron_left_rounded,
                      size: 28, color: gameInk)),
              title: Text(widget.game.title,
                  style: const TextStyle(
                      fontSize: 17,
                      color: gameInk,
                      fontWeight: FontWeight.w700))),
          body: Column(children: [
            if (_step > 0)
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 35, vertical: 14),
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
                        const SizedBox(height: 6),
                        Text(['邀请谁', '选玩法', '准备开场'][i],
                            style: TextStyle(
                                fontSize: 11,
                                color: i == _step ? gameRose : gameMuted))
                      ])
                    ]
                  ])),
            Expanded(
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                    children: _step == 0
                        ? _pick()
                        : _step == 1
                            ? _configure()
                            : _confirm())),
            Container(
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFF1EBF0))),
                    boxShadow: [
                      BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 14,
                          offset: Offset(0, -4))
                    ]),
                child: SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          if (_step == 0) _selectionSummary(),
                          if (_draft.validationError != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
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
                        ])))),
          ])));

  List<Widget> _pick() => [
        const Text('邀请谁一起玩',
            style: TextStyle(
                fontSize: 22,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: gameInk)),
        const SizedBox(height: 4),
        Text(
            widget.game == CompanionGame.truth
                ? '选 2～5 位搭子，开启轻松有趣的真心话小聚'
                : '选好人数板子和搭子，马上开启一局推理',
            style: const TextStyle(
                fontSize: 13, height: 1.45, color: gameMuted)),
        const SizedBox(height: 16),
        Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
                color: const Color(0xFFF1ECF0),
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              for (final from in [true, false])
                Expanded(
                    child: GestureDetector(
                        onTap: () => _selectSource(from),
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                                color: _fromGroup == from
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: _fromGroup == from
                                    ? const [
                                        BoxShadow(
                                            color: Color(0x12000000),
                                            blurRadius: 6,
                                            offset: Offset(0, 2))
                                      ]
                                    : null),
                            child: Text(from ? '已有群聊' : '我的搭子',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: _fromGroup == from
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _fromGroup == from
                                        ? gameInk
                                        : gameMuted)))))
            ])),
        const SizedBox(height: 14),
        if (widget.game == CompanionGame.wolf) ...[
          _seatChoices(),
          const SizedBox(height: 14)
        ],
        if (_fromGroup) ...[
          if (widget.groupsFailed)
            const Text('群聊暂时没读到，可返回娱乐页下拉重试，或从我的搭子组局。',
                style: TextStyle(color: gameMuted, height: 1.8)),
          if (widget.groups.isEmpty && !widget.groupsFailed)
            const Text('还没有群聊，可以切到「我的搭子」组局。',
                style: TextStyle(color: gameMuted, height: 1.8)),
          for (final g in widget.groups)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => setState(() {
                              _group = g;
                              _selected.clear();
                            }),
                        child: Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                                color: _group?.id == g.id
                                    ? const Color(0xFFFFF2F7)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: _group?.id == g.id
                                        ? gameRose
                                        : const Color(0xFFF0E9EE))),
                            child: Row(children: [
                              SizedBox(
                                  width: 54,
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
                                    const SizedBox(height: 4),
                                    Text('${g.activeMembers.length} 位搭子',
                                        style: const TextStyle(
                                            fontSize: 12, color: gameMuted))
                                  ])),
                              Icon(
                                  _group?.id == g.id
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 21,
                                  color:
                                      _group?.id == g.id ? gameRose : gameMuted)
                            ]))))),
          const SizedBox(height: 8),
        ],
        if (_available.isEmpty && !_fromGroup)
          TextButton.icon(
              onPressed: widget.onCreateRole,
              icon: const Icon(Icons.add),
              label: const Text('先创建我的搭子')),
        LayoutBuilder(builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
          final columns =
              (constraints.maxWidth < 300 || largeText) ? 2 : 3;
          const gap = 10.0;
          final itemWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          final avatarSize = (itemWidth - 28).clamp(52.0, 76.0);
          return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: _available.map((p) {
                final selected = _selected.contains(p.id);
                final disabled = !selected && _selected.length >= _max;
                return SizedBox(
                    width: itemWidth,
                    child: Semantics(
                        button: true,
                        selected: selected,
                        label: p.name,
                        child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                                onTap: disabled ? null : () => _toggle(p),
                                borderRadius: BorderRadius.circular(18),
                                child: Opacity(
                                    opacity: disabled ? .48 : 1,
                                    child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.fromLTRB(
                                            8, 12, 8, 10),
                                        decoration: BoxDecoration(
                                            color: selected
                                                ? const Color(0xFFFFF3F8)
                                                : Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            border: Border.all(
                                                color: selected
                                                    ? gameRose
                                                    : const Color(0xFFF0E9EE),
                                                width: selected ? 1.5 : 1),
                                            boxShadow: [
                                              BoxShadow(
                                                  color: selected
                                                      ? gameRose.withValues(
                                                          alpha: .12)
                                                      : const Color(0x07000000),
                                                  blurRadius:
                                                      selected ? 10 : 8,
                                                  offset: const Offset(0, 3))
                                            ]),
                                        child: Column(children: [
                                          Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                GamePortrait(p,
                                                    size: avatarSize),
                                                Positioned(
                                                    top: -4,
                                                    right: -4,
                                                    child: Container(
                                                        width: 21,
                                                        height: 21,
                                                        decoration: BoxDecoration(
                                                            color: selected
                                                                ? gameRose
                                                                : Colors.white,
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                                color: selected
                                                                    ? Colors
                                                                        .white
                                                                    : const Color(
                                                                        0xFFD0C9CF),
                                                                width: 1.5)),
                                                        child: selected
                                                            ? const Icon(
                                                                Icons
                                                                    .check_rounded,
                                                                size: 14,
                                                                color: Colors
                                                                    .white)
                                                            : null))
                                              ]),
                                          const SizedBox(height: 8),
                                          Text(p.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  height: 1.3,
                                                  fontWeight: selected
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: selected
                                                      ? gameRose
                                                      : gameInk))
                                        ])))))));
              }).toList());
        }),
      ];

  Widget _selectionSummary() => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('已选择 ${_chosen.length}/$_max 人',
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: gameInk)),
          const Spacer(),
          if (_chosen.isNotEmpty)
            TextButton(
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => setState(_selected.clear),
                child: const Text('清空',
                    style: TextStyle(color: gameRose, fontSize: 12.5)))
        ]),
        if (_chosen.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
              height: 36,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _chosen.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final p = _chosen[i];
                    return Container(
                        padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: gameRose.withValues(alpha: .22))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          GamePortrait(p, size: 26),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 84),
                              child: Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: gameInk))),
                          const SizedBox(width: 4),
                          GestureDetector(
                              onTap: () => _toggle(p),
                              child: const Icon(Icons.close_rounded,
                                  size: 15, color: gameMuted)),
                        ]));
                  })),
        ],
      ]));

  Widget _seatChoices() => Row(children: [
        for (final (seats, title, desc) in [
          (5, '5 人小局', '1狼 · 1预 · 3民'),
          (7, '7 人标准局', '2狼 · 1预 · 1巫 · 3民'),
        ]) ...[
          if (seats == 7) const SizedBox(width: 10),
          Expanded(
              child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() {
                            _seats = seats;
                            if (_seats == 5 && _identity == 'witch') {
                              _identity = null;
                            }
                            while (_selected.length > _max) {
                              _selected.remove(_selected.last);
                            }
                          }),
                      child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                              color: _seats == seats
                                  ? const Color(0xFFFFF2F7)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: _seats == seats
                                      ? gameRose
                                      : const Color(0xFFF0E9EE),
                                  width: _seats == seats ? 1.5 : 1)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: _seats == seats
                                                  ? gameRose
                                                  : gameInk))),
                                  Icon(
                                      _seats == seats
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      size: 17,
                                      color: _seats == seats
                                          ? gameRose
                                          : const Color(0xFFD0C9CF)),
                                ]),
                                const SizedBox(height: 3),
                                Text(desc,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11, color: gameMuted)),
                              ]))))),
        ],
      ]);

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
