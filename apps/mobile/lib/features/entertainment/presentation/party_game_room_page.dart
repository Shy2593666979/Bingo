import 'dart:async';
import 'dart:io';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/entertainment/data/party_game_gateway.dart';
import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/presentation/game_widgets.dart';
import 'package:bingo/features/entertainment/presentation/party_table.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/group_chat/presentation/group_call_page.dart';
import 'package:flutter/material.dart';

/// Only renders the server's player-specific projection. No local roles, votes or dialogue.
class PartyGameRoomPage extends StatefulWidget {
  const PartyGameRoomPage(
      {required this.gateway,
      required this.initial,
      required this.profile,
      super.key});
  final PartyGameGateway gateway;
  final Map<String, dynamic> initial;
  final UserProfile profile;
  @override
  State<PartyGameRoomPage> createState() => _PartyGameRoomPageState();
}

class _PartyGameRoomPageState extends State<PartyGameRoomPage>
    with WidgetsBindingObserver {
  late Map<String, dynamic> s = widget.initial;
  final input = TextEditingController();
  final scroll = ScrollController();
  Timer? timer;
  bool polling = false, busy = false, voice = false;
  String? networkError;
  ({String type, String value, String id, int revision, String stage})? retry;
  String get id => s['id'] as String;
  bool get finished => s['phase'] == 'finished';
  bool get truth => s['mode'] == 'truth';
  bool get paused => s['paused'] == true;
  List<GameCompanion> get people => (s['people'] as List)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .where((p) => p['id'] != 'self')
      .map((p) => GameCompanion(
          id: p['id'] as String,
          name: p['name'] as String,
          avatarKey: p['avatar_key'] as String? ?? ''))
      .toList();
  Map<String, dynamic> get choices =>
      Map<String, dynamic>.from(s['options'] as Map? ?? {});

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(milliseconds: 800), (_) => refresh());
  }

  void update(Map<String, dynamic> next) {
    if (!mounted || (next['revision'] as int) < (s['revision'] as int)) return;
    final changed = next['revision'] != s['revision'];
    if (!changed && next['processing'] == s['processing']) return;
    final follow = !scroll.hasClients ||
        scroll.position.maxScrollExtent - scroll.offset < 100;
    setState(() {
      s = next;
      networkError = null;
    });
    if (follow && changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut);
        }
      });
    }
  }

  Future<void> refresh() async {
    if (polling || finished || !mounted) return;
    polling = true;
    try {
      update(await widget.gateway.getPartyGame(id));
    } catch (_) {
      if (mounted) setState(() => networkError = '连接暂时中断，正在重新连接');
    } finally {
      polling = false;
    }
  }

  Future<void> act(String type, [String value = '']) async {
    if (busy || finished) return;
    final pending = retry ??
        (
          type: type,
          value: value,
          id: 'game-${DateTime.now().microsecondsSinceEpoch}',
          revision: s['revision'] as int,
          stage: s['action_stage'] as String? ?? '',
        );
    setState(() => busy = true);
    try {
      update(await widget.gateway.partyGameAction(
          id, pending.type, pending.value, pending.revision, pending.id,
          stage: pending.stage));
      retry = null;
      if (pending.type == 'say') input.clear();
    } catch (error) {
      final rejected =
          error is ApiException && {409, 422, 404}.contains(error.statusCode);
      retry = rejected ? null : pending;
      if (mounted) {
        showCenterToast(
            context, rejected ? error.toString() : '操作未确认，可重试；不会重复提交');
      }
      await refresh();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startVoice() async {
    if (busy || voice || finished) return;
    final members = people
        .map((p) => GroupPerson.fromJson({
              'id': p.id,
              'name': p.name,
              'role_name': p.avatarKey,
              'active': true,
            }))
        .toList();
    final group = ChatGroup.fromJson({
      'id': id,
      'name': truth ? '真心话小聚' : '搭子推理局',
      'cover': 'coffee',
      'members': members
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'role_name': p.roleName,
                'active': true,
              })
          .toList(),
      'human': {'id': 'self', 'name': widget.profile.username ?? '我'},
      'last_activity_at': DateTime.now().toIso8601String()
    });
    setState(() => voice = true);
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => GroupCallPage(
                group: group,
                members: members,
                gateway: _GameVoiceGateway(widget.gateway),
                gameSession: true,
                userAvatarData: widget.profile.userAvatarData)));
    if (mounted) {
      setState(() => voice = false);
      await refresh();
    }
  }

  void identity() {
    final data = Map<String, dynamic>.from(s['private'] as Map);
    const names = {
      'wolf': '狼人',
      'seer': '预言家',
      'witch': '女巫',
      'villager': '村民'
    };
    String playerName(String id) => id == 'self'
        ? '你'
        : people.where((p) => p.id == id).firstOrNull?.name ?? id;
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(names[data['identity']] ?? '本局信息'),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      if (data['teammates'] is List)
                        Text(
                            '狼队：${(data['teammates'] as List).map((p) => playerName(p as String)).join('、')}'),
                      for (final clue in data['clues'] as List? ?? [])
                        Text(
                            '第 ${clue['day']} 夜：${playerName(clue['target'] as String)}是${clue['wolf'] == true ? '狼人' : '好人'}'),
                      if (data['potions'] is Map)
                        Text(
                            '解药：${data['potions']['save'] == true ? '可用' : '已用'}　毒药：${data['potions']['poison'] == true ? '可用' : '已用'}'),
                      if (data['victim'] is String)
                        Text('今晚被袭击的是：${playerName(data['victim'] as String)}'),
                      const SizedBox(height: 12),
                      const Text('此处仅显示你自己获知的信息。'),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('知道了'))
                ]));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Widget controls() => Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 9),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: double.infinity,
            child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  PopupMenuButton<String>(
                      tooltip: '轮次操作',
                      onSelected: (value) {
                        if (value == 'voice') {
                          startVoice();
                        } else {
                          act(value);
                        }
                      },
                      itemBuilder: (_) => [
                            PopupMenuItem(
                                value: paused ? 'resume' : 'pause',
                                child: Text(paused ? '继续游戏' : '先停一会儿')),
                            const PopupMenuItem(
                                value: 'voice', child: Text('切换语音'))
                          ],
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                              border: Border.all(color: gameLine),
                              borderRadius: BorderRadius.circular(22)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(
                                '第 ${s['round']} ${truth ? '轮' : s['phase'] == 'night' ? '夜' : '天'}',
                                style: const TextStyle(
                                    fontSize: 13, color: gameInk)),
                            const Icon(Icons.expand_more,
                                size: 17, color: gameInk)
                          ]))),
                  if (s['can_advance'] == true && !paused)
                    OutlinedButton(
                        onPressed: busy || paused || retry != null
                            ? null
                            : () => act('advance'),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: gameRose),
                            shape: const StadiumBorder()),
                        child: Text(truth ? '下一轮 ›' : '进入投票',
                            style: const TextStyle(
                                fontSize: 13, color: gameRose))),
                  if (paused)
                    TextButton(
                        onPressed:
                            busy || retry != null ? null : () => act('resume'),
                        child: const Text('继续游戏')),
                ])),
        if (s['action_hint'] is String)
          Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Text(s['action_hint'] as String,
                      style: const TextStyle(fontSize: 12, color: gameMuted)))),
        if (choices.isNotEmpty ||
            (truth && s['actor'] == 'self' && s['phase'] == 'answer'))
          ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .28),
              child: SingleChildScrollView(
                  child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final option in choices.entries)
                  ActionChip(
                      label: Text(option.value.toString()),
                      onPressed: busy || paused || retry != null
                          ? null
                          : () => act('choice', option.key)),
                if (truth && s['actor'] == 'self' && s['phase'] == 'answer')
                  ActionChip(
                      label: const Text('换一题'),
                      onPressed: busy || paused || retry != null
                          ? null
                          : () => act('change_question')),
              ]))),
      ]));

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = s['phase'] as String;
    final paused = s['paused'] == true;
    const phases = {
      'select': '邀请参与者',
      'choose': '选择玩法',
      'question': '正在出题',
      'answer': '回答问题',
      'discuss': '自由讨论',
      'night': '夜间行动',
      'speech': '白天发言',
      'last_words': '遗言',
      'vote': '独立投票',
      'finished': '本局结束'
    };
    final canSpeak = !finished &&
        !paused &&
        (s['can_speak'] == true ||
            truth ||
            (phase == 'speech' && (s['alive'] as List).contains('self')));
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
            backgroundColor: Colors.white,
            centerTitle: true,
            title: Transform.translate(
                offset: const Offset(0, 12),
                child: Text(truth ? '真心话小聚' : '搭子推理局',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600))),
            actions: [
              PopupMenuButton<String>(
                  tooltip: '游戏操作',
                  icon: Transform.translate(
                      offset: const Offset(0, 12),
                      child: const Icon(Icons.more_horiz)),
                  onSelected: (v) {
                    if (v == 'voice') {
                      startVoice();
                    } else if (v == 'identity') {
                      identity();
                    } else if (v == 'end') {
                      showDialog<void>(
                          context: context,
                          builder: (dialog) => AlertDialog(
                                  title: const Text('结束本局？'),
                                  content: const Text('当前记录会保留，结束后不能继续本局。'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(dialog),
                                        child: const Text('再玩一会')),
                                    TextButton(
                                        onPressed: () {
                                          Navigator.pop(dialog);
                                          act('end');
                                        },
                                        child: const Text('结束'))
                                  ]));
                    } else {
                      act(v);
                    }
                  },
                  itemBuilder: (_) => [
                        if (!finished)
                          const PopupMenuItem(
                              value: 'voice', child: Text('切换语音')),
                        if (!truth)
                          const PopupMenuItem(
                              value: 'identity', child: Text('我的身份与线索')),
                        if (!finished)
                          PopupMenuItem(
                              value: paused ? 'resume' : 'pause',
                              child: Text(paused ? '继续游戏' : '先停一会儿')),
                        if (!finished)
                          const PopupMenuItem(value: 'end', child: Text('结束本局'))
                      ])
            ]),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 14),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFCEBF2),
                      borderRadius: BorderRadius.circular(25)),
                  child: Text(
                      '第 ${s['round']} ${truth ? '轮' : phase == 'night' ? '夜' : '天'} · ${paused ? '已暂停' : phases[phase] ?? phase}',
                      style: const TextStyle(fontSize: 14, color: gameInk)))),
          PartySeatStrip(
              people: people,
              hostId: s['host_id'] as String?,
              username: widget.profile.username ?? '我',
              userAvatarData: widget.profile.userAvatarData,
              eliminatedIds: {
                for (final p in s['people'] as List)
                  if (!(s['alive'] as List).contains(p['id'])) p['id'] as String
              },
              activeId: s['actor'] as String?),
          if (networkError != null || s['error'] != null)
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text(networkError ?? s['error'] as String,
                    style: const TextStyle(color: gameRose, fontSize: 12))),
          if (retry != null)
            TextButton(
                onPressed: busy ? null : () => act(retry!.type, retry!.value),
                child: const Text('重试上一次操作')),
          Expanded(
              child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      children: [
                        for (final item in s['messages'] as List)
                          bubble(Map<String, dynamic>.from(item as Map)),
                        if (!finished && s['processing'] == true)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('搭子正在组织语言…',
                                  style: TextStyle(
                                      fontSize: 12, color: gameMuted))),
                        if (!finished && s['waiting_user'] == true)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('大家在等你回应，也可以跳过这一轮',
                                  style: TextStyle(
                                      fontSize: 12, color: gameMuted))),
                        if (finished && s['identities'] is Map) ...[
                          const SizedBox(height: 20),
                          const Text('身份揭晓',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                          for (final person in s['people'] as List)
                            Text(
                                '${person['name']}：${{
                                  'wolf': '狼人',
                                  'seer': '预言家',
                                  'witch': '女巫',
                                  'villager': '村民'
                                }[s['identities'][person['id']]]}',
                                style: const TextStyle(height: 2)),
                        ],
                      ]))),
          if (!finished) controls(),
          if (finished)
            Padding(
                padding: const EdgeInsets.all(18),
                child: GameButton('返回娱乐页',
                    onPressed: () => Navigator.pop(context))),
          if (!finished)
            SafeArea(
                top: false,
                child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
                    decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: gameLine))),
                    child: Row(children: [
                      IconButton(
                          onPressed: startVoice,
                          tooltip: '语音游戏',
                          icon: const Icon(Icons.mic_none_rounded)),
                      Expanded(
                          child: TextField(
                              controller: input,
                              enabled: canSpeak && !busy && retry == null,
                              minLines: 1,
                              maxLines: 3,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (v) => act('say', v),
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                  hintText: canSpeak ? '说点什么吧…' : '等待当前阶段完成',
                                  filled: true,
                                  fillColor: const Color(0xFFF7F6F8),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(25),
                                      borderSide:
                                          const BorderSide(color: gameLine)),
                                  suffixIcon: IconButton(
                                      tooltip: '发送',
                                      onPressed:
                                          canSpeak && !busy && retry == null
                                              ? () => act('say', input.text)
                                              : null,
                                      icon: Icon(
                                          busy
                                              ? Icons.more_horiz
                                              : Icons.arrow_upward_rounded,
                                          color: gameRose))))),
                    ]))),
        ]));
  }

  Widget bubble(Map<String, dynamic> m) {
    final speaker = m['speaker'] as String?;
    if (speaker == null) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(m['text'] as String,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: gameMuted)));
    }
    final self = speaker == 'self';
    final person = people.where((p) => p.id == speaker).firstOrNull;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                self ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!self && person != null) ...[
                GamePortrait(person, size: 46),
                const SizedBox(width: 10)
              ],
              Flexible(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: self ? 240 : 250),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!self)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Text(person?.name ?? '',
                                      style: const TextStyle(
                                          fontSize: 12, color: gameMuted))),
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 13, vertical: 8),
                                decoration: BoxDecoration(
                                    color: self
                                        ? const Color(0xFFE7FECC)
                                        : speaker == s['host_id']
                                            ? const Color(0xFFFCE9F1)
                                            : const Color(0xFFF5F3F4),
                                    borderRadius: BorderRadius.circular(18)),
                                child: Text(m['text'] as String,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.35,
                                        color: gameInk))),
                          ]))),
            ]));
  }
}

class _GameVoiceGateway implements GroupCallGateway {
  _GameVoiceGateway(this.gateway);
  final PartyGameGateway gateway;
  @override
  Future<WebSocket> connectGroupCall(String groupId, List<String> roleIds) =>
      gateway.connectPartyVoice(groupId);
}
