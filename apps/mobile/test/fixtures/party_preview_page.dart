import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/presentation/game_widgets.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'party_preview_session.dart';
export 'party_preview_session.dart';
import 'package:bingo/features/entertainment/presentation/party_table.dart';

class GamePreviewPage extends StatefulWidget {
  const GamePreviewPage(
      {required this.session, required this.profile, super.key});
  final GamePreviewSession session;
  final UserProfile profile;
  @override
  State<GamePreviewPage> createState() => _GamePreviewPageState();
}

class _GamePreviewPageState extends State<GamePreviewPage>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  GamePreviewSession get s => widget.session;
  String get username => widget.profile.username?.trim().isNotEmpty == true
      ? widget.profile.username!
      : '我';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.addListener(_onSessionChanged);
    _input.addListener(_onDraft);
    s.activate();
  }

  void _onDraft() {
    s.setComposing(_input.text.trim().isNotEmpty);
    if (mounted) setState(() {});
  }

  GameCompanion get _host =>
      s.setup.companions.firstWhere((p) => p.avatarKey.contains('老师'),
          orElse: () => s.setup.companions.first);
  void _onSessionChanged() {
    if (!mounted) return;
    final follow = !_scroll.hasClients ||
        _scroll.position.maxScrollExtent - _scroll.offset < 96;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && follow && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      s.activate();
    } else {
      s.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(_onSessionChanged);
    s.suspend();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _change(VoidCallback fn) {
    setState(fn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _send() {
    final value = _input.text;
    if (value.trim().isEmpty) return;
    _input.clear();
    _change(() => s.send(value));
  }

  Future<void> _showIdentity() async {
    s.suspend();
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFFFFFBFE),
        builder: (context) => SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _identityCard(),
                  const SizedBox(height: 18),
                  GameButton('回到游戏房', onPressed: () => Navigator.pop(context))
                ]))));
    if (mounted) s.activate();
  }

  Future<void> _players() async {
    s.suspend();
    await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('本局玩家',
                          style: TextStyle(fontSize: 18, color: gameInk)),
                      const SizedBox(height: 20),
                      GameRoster(
                          people: s.setup.companions,
                          username: username,
                          userAvatarData: widget.profile.userAvatarData)
                    ]))));
    if (mounted) s.activate();
  }

  Future<void> _end() async {
    s.suspend();
    final end = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('结束本次体验？'),
                content: const Text('也可以先返回娱乐页，稍后继续这次体验。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('继续体验')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('结束体验'))
                ]));
    if (end == true && mounted) _change(s.endExperience);
    if (mounted && !s.finished) s.activate();
  }

  @override
  Widget build(BuildContext context) {
    final chatting =
        [PreviewPhase.truth, PreviewPhase.discussion].contains(s.phase);
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
            leading: Transform.translate(
                offset: const Offset(0, 12),
                child: IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.chevron_left_rounded,
                        size: 28, color: gameInk))),
            centerTitle: true,
            backgroundColor: Colors.white,
            title: Transform.translate(
                offset: const Offset(0, 12),
                child: Text(
                    s.phase == PreviewPhase.result ? '本局回顾' : s.setup.roomName,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: gameInk))),
            actions: [
              PopupMenuButton<String>(
                  icon: Transform.translate(
                      offset: const Offset(0, 12),
                      child: const Icon(Icons.more_horiz,
                          size: 24, color: gameInk)),
                  tooltip: '游戏操作',
                  onSelected: (value) {
                    if (value == 'players') _players();
                    if (value == 'identity') _showIdentity();
                    if (value == 'end') _end();
                    if (value == 'next') _change(s.nextRound);
                  },
                  itemBuilder: (_) => [
                        const PopupMenuItem<String>(
                            enabled: false, child: Text('本地剧情体验 · 尚未接入 AI')),
                        const PopupMenuItem(
                            value: 'players', child: Text('本局玩家')),
                        if (s.setup.game == CompanionGame.wolf)
                          const PopupMenuItem(
                              value: 'identity', child: Text('我的身份')),
                        if (s.setup.game == CompanionGame.truth)
                          const PopupMenuItem(
                              value: 'next', child: Text('提前结束本轮')),
                        const PopupMenuItem(value: 'end', child: Text('结束体验'))
                      ])
            ]),
        body: Column(children: [
          if (chatting) _phaseBar(),
          if (chatting && !s.voice)
            PartySeatStrip(
                people: s.setup.companions,
                username: username,
                userAvatarData: widget.profile.userAvatarData,
                activeId: s.awaitingUser ? 'self' : s.activeSpeakerId,
                hostId: _host.id),
          Expanded(
              child: chatting && s.voice
                  ? _voice()
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      children: switch (s.phase) {
                        PreviewPhase.identity => [
                            _identityCard(),
                            const SizedBox(height: 23),
                            const Text('本局玩家',
                                style: TextStyle(fontSize: 16, color: gameInk)),
                            const SizedBox(height: 16),
                            GameRoster(
                                people: s.setup.companions,
                                username: username,
                                userAvatarData: widget.profile.userAvatarData)
                          ],
                        PreviewPhase.night => _night(),
                        PreviewPhase.vote => _voting(),
                        PreviewPhase.result => _result(),
                        _ => [
                            for (final message in s.messages) _message(message)
                          ],
                      })),
          if (s.phase == PreviewPhase.identity)
            _footer(GameButton('知道了，看看夜间行动',
                onPressed: () => _change(() => s.phase = PreviewPhase.night))),
          if (s.phase == PreviewPhase.night)
            _footer(GameButton('确认查验',
                onPressed: s.target == null ? null : _check)),
          if (s.phase == PreviewPhase.vote)
            _footer(GameButton(s.voteLocked ? '查看体验回顾' : '确认投票',
                onPressed: s.vote == null
                    ? null
                    : s.voteLocked
                        ? () => _change(s.endExperience)
                        : _confirmVote)),
          if (s.phase == PreviewPhase.result)
            _footer(
                GameButton('返回娱乐页', onPressed: () => Navigator.pop(context))),
          if (chatting) ...[_actions(), _composer()],
        ]));
  }

  Widget _phaseBar() => Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 14),
      child: Center(
          child: Stack(clipBehavior: Clip.none, children: [
        InkWell(
            onTap: () => _change(() => s.voice = !s.voice),
            borderRadius: BorderRadius.circular(25),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
                decoration: BoxDecoration(
                    color: const Color(0xFFFCEBF2),
                    borderRadius: BorderRadius.circular(25)),
                child: SizedBox(
                    width: 140,
                    child: Text(
                        s.phase == PreviewPhase.truth
                            ? '第 ${s.round} 轮 · ${s.kind ?? "真心话"}'
                            : '第 1 天 · 讨论中',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, height: 1.3, color: gameInk))))),
        const Positioned(right: -26, top: -5, child: GameAccent()),
      ])));

  Widget _identityCard() => GameSurface(
      lilac: true,
      child: Column(children: [
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_outline, size: 14, color: gameLilac),
          SizedBox(width: 5),
          Text('示例身份 · 仅你可见', style: TextStyle(fontSize: 11, color: gameLilac))
        ]),
        const SizedBox(height: 30),
        const Icon(Icons.visibility_outlined, size: 76, color: gameLilac),
        const SizedBox(height: 20),
        const Text('预言家',
            style: TextStyle(
                fontSize: 30, color: gameInk, fontWeight: FontWeight.w600)),
        const SizedBox(height: 15),
        const Text('每晚查验一位存活玩家的阵营。\n用你的判断，帮助好人找出狼人。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 2, color: gameMuted)),
        const SizedBox(height: 17),
        const Text('这里展示身份页样式；正式对局由服务端随机分配身份。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, height: 1.8, color: gameMuted))
      ]));

  List<Widget> _night() => [
        const GameSectionTitle('今晚想查验谁？', subtitle: '第 1 夜 · 私密操作，不发送到公共聊天。'),
        ...s.setup.companions.map((p) =>
            _target(p, s.target == p.id, () => _change(() => s.target = p.id))),
        const SizedBox(height: 15),
        const Text('当前是操作样式演示，不产生真实阵营结果。',
            style: TextStyle(fontSize: 11, height: 1.8, color: gameMuted))
      ];
  Future<void> _check() async {
    final person = s.setup.companions.firstWhere((p) => p.id == s.target);
    final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('私密查验 · 结果页预览'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  GamePortrait(person, size: 70),
                  const SizedBox(height: 12),
                  Text(person.name),
                  const SizedBox(height: 10),
                  const Text('阵营结果将在正式对局中显示。\n此处仅展示私密结果的承接方式。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: gameMuted, height: 1.8))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('看看白天讨论'))
                ]));
    if (proceed == true && mounted) _change(s.beginDay);
  }

  Widget _target(GameCompanion p, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
          color: selected ? const Color(0xFFFFF0F7) : Colors.white,
          shape: RoundedRectangleBorder(
              side: BorderSide(color: selected ? gameRose : gameLine),
              borderRadius: BorderRadius.circular(16)),
          child: ListTile(
              onTap: onTap,
              leading: GamePortrait(p, size: 43),
              title: Text(p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: gameInk)),
              trailing: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? gameRose : gameMuted,
                  size: 21))));

  List<Widget> _voting() => [
        const GameSectionTitle('这一票，你想投给谁？', subtitle: '第 1 天 · 正式投票与公开讨论分开。'),
        if (s.voteLocked)
          const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Text('体验投票已锁定。正式对局会等待所有存活玩家提交后统一公布。',
                  style: TextStyle(color: gameRose, height: 1.8))),
        for (final p in s.setup.companions)
          _target(p, s.vote == p.id, () {
            if (!s.voteLocked) _change(() => s.vote = p.id);
          }),
        _voteOwn(),
        const SizedBox(height: 7),
        OutlinedButton(
            onPressed:
                s.voteLocked ? null : () => _change(() => s.vote = 'abstain'),
            child: Text(s.vote == 'abstain' ? '✓ 已选择弃票' : '弃票'))
      ];
  Widget _voteOwn() => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ListTile(
          shape: RoundedRectangleBorder(
              side: BorderSide(color: s.vote == 'self' ? gameRose : gameLine),
              borderRadius: BorderRadius.circular(16)),
          onTap: s.voteLocked ? null : () => _change(() => s.vote = 'self'),
          leading: UserAvatar(
              username: username,
              avatarData: widget.profile.userAvatarData,
              size: 43),
          title: Text('$username（你）',
              style: const TextStyle(fontSize: 14, color: gameInk)),
          trailing: Icon(
              s.vote == 'self'
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 21,
              color: gameRose)));
  Future<void> _confirmVote() async {
    final target = s.vote == 'abstain'
        ? '弃票'
        : '投给${s.vote == 'self' ? username : s.setup.companions.firstWhere((p) => p.id == s.vote).name}';
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('确认$target？'),
                content: const Text('确认后本次体验投票不可修改。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('再想想')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认'))
                ]));
    if (confirmed == true && mounted) _change(() => s.voteLocked = true);
  }

  Widget _message(PreviewMessage message) {
    if (message.banner) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: GameSurface(
              padding: const EdgeInsets.all(14),
              child: Text(message.text,
                  style: const TextStyle(
                      fontSize: 13,
                      color: gameRose,
                      fontWeight: FontWeight.w500))));
    }
    final user = message.user;
    final host = !user && message.person == null;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                user ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!user) ...[
                GamePortrait(message.person ?? _host, size: 46),
                const SizedBox(width: 10)
              ],
              Flexible(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: user
                              ? 240
                              : host
                                  ? 262
                                  : 250),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!user) ...[
                              Text.rich(
                                  TextSpan(
                                      text: message.person?.name ?? _host.name,
                                      children: [
                                        if (host)
                                          const TextSpan(
                                              text: ' · 主持人',
                                              style: TextStyle(color: gameRose))
                                      ]),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.3,
                                      color: gameInk)),
                              const SizedBox(height: 4),
                            ],
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 13, vertical: 8),
                                decoration: BoxDecoration(
                                    color: user
                                        ? const Color(0xFFE7FECC)
                                        : host
                                            ? const Color(0xFFFCE9F1)
                                            : const Color(0xFFF5F3F4),
                                    borderRadius: BorderRadius.circular(18)),
                                child: Text(message.text,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.35,
                                        color: gameInk))),
                          ]))),
            ]));
  }

  Widget _actions() => Padding(
      padding: const EdgeInsets.fromLTRB(14, 3, 14, 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PopupMenuButton<String>(
              key: const ValueKey('game-round-menu'),
              onSelected: (v) {
                if (v == 'pause') {
                  s.paused ? s.resume() : s.pause();
                }
                if (v == 'voice') _change(() => s.voice = !s.voice);
              },
              itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'pause', child: Text(s.paused ? '继续' : '先停一会儿')),
                    const PopupMenuItem(
                        value: 'voice', child: Text('切换文字 / 语音'))
                  ],
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                      border: Border.all(color: gameLine),
                      borderRadius: BorderRadius.circular(22)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('第 ${s.round} 轮',
                        style: const TextStyle(fontSize: 13, color: gameInk)),
                    const Icon(Icons.expand_more, size: 17, color: gameInk)
                  ]))),
          const Spacer(),
          if (s.phase == PreviewPhase.truth)
            OutlinedButton(
                onPressed: () => _change(s.nextRound),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: gameRose),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(88, 34)),
                child: const Text('下一轮 ›',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: gameRose))),
        ]),
        if (s.phase == PreviewPhase.truth &&
            s.userTurn &&
            s.awaitingUser &&
            !s.paused)
          Wrap(spacing: 7, children: [
            if (s.awaitingChoice) ...[
              for (final kind in ['真心话', '大冒险'])
                ActionChip(
                    label: Text(kind),
                    onPressed: () => _change(() => s.choose(kind)))
            ],
            if (!s.awaitingChoice)
              ActionChip(
                  label: const Text('换一题'),
                  onPressed: () => _change(() {
                        s.questionIndex++;
                        s.choose(s.kind ?? '真心话');
                      })),
            ActionChip(
                label: const Text('我先听大家聊'),
                onPressed: () => _change(s.nextRound)),
          ]),
        if (s.phase == PreviewPhase.discussion)
          Wrap(spacing: 8, children: [
            ActionChip(label: const Text('我的身份'), onPressed: _showIdentity),
            ActionChip(
                label: const Text('进入投票'),
                onPressed: () => _change(s.beginVote)),
          ]),
      ]));
  Widget _composer() => SafeArea(
      top: false,
      child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 24),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: gameLine))),
          child: Row(children: [
            IconButton(
                onPressed: _players,
                tooltip: '本局玩家',
                icon: const Icon(Icons.add_circle_outline,
                    color: gameMuted, size: 26)),
            Expanded(
                child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                        isDense: true,
                        hintText: '说点什么吧…',
                        hintStyle:
                            const TextStyle(color: gameMuted, fontSize: 14),
                        fillColor: const Color(0xFFF7F6F8),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        suffixIconConstraints:
                            const BoxConstraints(minWidth: 40, minHeight: 38),
                        suffixIcon: IconButton(
                            tooltip: '发送',
                            onPressed: _send,
                            icon: Icon(
                                _input.text.isEmpty
                                    ? Icons.sentiment_satisfied_alt_outlined
                                    : Icons.arrow_upward_rounded,
                                size: 24,
                                color: _input.text.isEmpty
                                    ? gameMuted
                                    : gameRose)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(color: gameLine)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(color: gameLine))))),
          ])));

  Widget _voice() => Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          PartyTable(
              caption: '同一桌，聊着玩',
              activeId: s.awaitingUser ? 'self' : s.activeSpeakerId,
              people: s.setup.companions,
              username: username,
              userAvatarData: widget.profile.userAvatarData),
          const SizedBox(height: 27),
          GameSurface(
              child: Column(children: [
            const Text('游戏语音房', style: TextStyle(fontSize: 16, color: gameInk)),
            const SizedBox(height: 10),
            const Text('语音界面预览 · 当前未连接通话',
                style: TextStyle(fontSize: 12, color: gameMuted)),
            const SizedBox(height: 14),
            Text(
                s.phase == PreviewPhase.truth
                    ? '第 ${s.round} 轮 · 轮到${s.actor}'
                    : '第 1 天 · 讨论中',
                style: const TextStyle(fontSize: 13, color: gameRose))
          ])),
          const SizedBox(height: 20),
          const Text('聊天记录', style: TextStyle(fontSize: 12, color: gameMuted)),
          for (final m in s.messages
              .skip(s.messages.length > 3 ? s.messages.length - 3 : 0))
            _message(m),
          const SizedBox(height: 20),
        ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _voiceControl(Icons.mic_off_outlined, '麦克风',
                      () => showCenterToast(context, '真实游戏语音尚未开放，可先用文字体验')),
                  _voiceControl(Icons.call_end_rounded, '挂断回文字',
                      () => _change(() => s.voice = false),
                      hang: true),
                  _voiceControl(Icons.volume_up_outlined, '扬声器',
                      () => showCenterToast(context, '当前为语音房界面预览'))
                ]))
      ]);
  Widget _voiceControl(IconData icon, String title, VoidCallback onTap,
          {bool hang = false}) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(children: [
            IconButton.filled(
                onPressed: onTap,
                icon: Icon(icon),
                style: IconButton.styleFrom(
                    backgroundColor: hang
                        ? const Color(0xFFDF7C99)
                        : const Color(0xFFF4E6EF),
                    foregroundColor: hang ? Colors.white : gameMuted,
                    padding: const EdgeInsets.all(15))),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 11, color: gameMuted))
          ]));
  List<Widget> _result() => [
        GameSurface(
            child: Column(children: [
          const Icon(Icons.auto_awesome, size: 40, color: gameRose),
          const SizedBox(height: 20),
          const Text('这次体验，先到这里。',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w600, color: gameInk)),
          const SizedBox(height: 12),
          Text('${s.setup.game.title} · 界面体验完成',
              style: const TextStyle(fontSize: 13, color: gameMuted)),
          const SizedBox(height: 24),
          GameRoster(
              people: s.setup.companions,
              username: username,
              userAvatarData: widget.profile.userAvatarData)
        ])),
        const SizedBox(height: 20),
        const Text('一起说过的话',
            style: TextStyle(
                fontSize: 17, color: gameInk, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (s.messages.any((m) => m.user))
          ...s.messages.where((m) => m.user).map(_message)
        else
          const Text('这一局还没有留下体验发言。',
              style: TextStyle(fontSize: 12, color: gameMuted)),
        const SizedBox(height: 20),
        const Text('当前预览不计算胜负、不写入群聊天记录，也不会保存共同回忆。正式 AI 对局接入后，再展示真实结算与复盘。',
            style: TextStyle(fontSize: 12, height: 1.9, color: gameMuted))
      ];
  Widget _footer(Widget child) => SafeArea(
      top: false,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 12, 17, 17), child: child));
}
