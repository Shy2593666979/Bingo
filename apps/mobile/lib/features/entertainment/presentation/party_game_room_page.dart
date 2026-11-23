import 'dart:async';
import 'dart:io';
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/core/design/chat_scene.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/message_presentation_store.dart';
import 'package:bingo/features/chat/presentation/widgets/local_message_view.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/entertainment/data/party_game_gateway.dart';
import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/presentation/game_widgets.dart';
import 'package:bingo/features/entertainment/presentation/party_reply_presenter.dart';
import 'package:bingo/features/entertainment/presentation/party_table.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/group_chat/presentation/group_call_page.dart';
import 'package:bingo/shared/widgets/speaking_wave.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late Map<String, dynamic> s = widget.initial;
  final input = TextEditingController();
  final scroll = ScrollController();
  late final PartyReplyPresenter _replies = PartyReplyPresenter(
    gateway: widget.gateway,
    gameId: widget.initial['id'] as String,
    onError: () {
      if (mounted) showCenterToast(context, '语音朗读暂时不可用，文字内容不受影响');
    },
  );
  final List<Map<String, dynamic>> _optimistic = [];
  Timer? timer;
  Timer? _identityIntroTimer;
  late final AnimationController _identityIntroCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    reverseDuration: const Duration(milliseconds: 420),
  );
  bool _showIdentityIntro = false;
  bool _sheetOpen = false;
  String? _promptedModalStage;
  String? _lastActivePhase;
  bool polling = false, busy = false, voice = false, revealIdentity = false;
  bool? _localReadAloud;
  String? networkError;
  ({String type, String value, String id, int revision, String stage})? retry;
  String get id => s['id'] as String;
  bool get finished => s['phase'] == 'finished';
  bool get showFinished => finished && !_replies.busy;
  bool get truth => s['mode'] == 'truth';
  bool get paused => s['paused'] == true;
  bool get readAloud => _localReadAloud ?? (s['read_aloud'] != false);
  bool get nightMode => !truth && s['phase'] == 'night';
  SpeechGateway get _speechGateway => widget.gateway is SpeechGateway
      ? widget.gateway as SpeechGateway
      : const _NoopSpeechGateway();
  String? get myIdentity =>
      (s['private'] as Map?)?['identity'] as String?;
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

  static const _roleMeta = <String,
      ({String name, String camp, String tip, Color color, IconData icon})>{
    'wolf': (
      name: '狼人',
      camp: '狼人阵营',
      tip: '每晚与狼队友商议并袭击一名玩家，白天隐藏好身份',
      color: Color(0xFFD94A5A),
      icon: Icons.nights_stay_rounded,
    ),
    'seer': (
      name: '预言家',
      camp: '好人阵营',
      tip: '每晚可查验一名存活玩家是好人还是狼人',
      color: Color(0xFF7B61FF),
      icon: Icons.visibility_rounded,
    ),
    'witch': (
      name: '女巫',
      camp: '好人阵营',
      tip: '拥有解药与毒药各一瓶，每晚最多用一瓶，首夜可自救',
      color: Color(0xFF2B8A7E),
      icon: Icons.science_rounded,
    ),
    'villager': (
      name: '村民',
      camp: '好人阵营',
      tip: '仔细听清每位搭子的发言与票型，找出隐藏的狼人',
      color: Color(0xFF6B7280),
      icon: Icons.person_outline_rounded,
    ),
  };

  String _playerName(String playerId) => playerId == 'self'
      ? '你'
      : people.where((p) => p.id == playerId).firstOrNull?.name ?? playerId;

  String? _seatTag(String playerId) {
    if (truth) return null;
    if (playerId == 'self') return '${people.length + 1}号';
    final idx = people.indexWhere((p) => p.id == playerId);
    return idx >= 0 ? '${idx + 1}号' : null;
  }

  @override
  void initState() {
    super.initState();
    final initialPhase = s['phase'] as String?;
    if (initialPhase != null && initialPhase != 'finished') {
      _lastActivePhase = initialPhase;
    }
    WidgetsBinding.instance.addObserver(this);
    _replies.addListener(_onPresenterChanged);
    _syncPresenter();
    if (!truth && !finished && myIdentity != null) {
      _showIdentityIntro = true;
      _identityIntroCtrl.forward();
      _identityIntroTimer =
          Timer(const Duration(seconds: 2), _dismissIdentityIntro);
    } else {
      _maybeOpenActionModal();
    }
    timer = Timer.periodic(const Duration(milliseconds: 800), (_) => refresh());
  }

  Future<void> _dismissIdentityIntro() async {
    _identityIntroTimer?.cancel();
    _identityIntroTimer = null;
    if (!mounted || !_showIdentityIntro) return;
    await _identityIntroCtrl.reverse();
    if (mounted) {
      setState(() => _showIdentityIntro = false);
      _maybeOpenActionModal();
    }
  }

  bool get _hasModalAction =>
      !truth &&
      !finished &&
      !paused &&
      choices.isNotEmpty &&
      (s['phase'] == 'vote' || s['phase'] == 'night');

  void _maybeOpenActionModal() {
    if (!mounted || !_hasModalAction || _replies.busy || _showIdentityIntro || _sheetOpen) {
      return;
    }
    final stageKey =
        '${s['round']}:${s['phase']}:${s['action_stage'] ?? ''}:${choices.keys.join(',')}';
    if (_promptedModalStage == stageKey) return;
    _promptedModalStage = stageKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hasModalAction && !_replies.busy && !_showIdentityIntro && !_sheetOpen) {
        unawaited(_openActionModal());
      }
    });
  }

  void _onPresenterChanged() {
    if (!mounted) return;
    final follow = !scroll.hasClients ||
        scroll.position.maxScrollExtent - scroll.offset < 120;
    setState(() {});
    if (follow) _scrollToBottom();
    _maybeOpenActionModal();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut);
      }
    });
  }

  void _syncPresenter() {
    final raw = (s['messages'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _replies.update(raw, sound: readAloud, enabled: !voice && !paused);
  }

  void update(Map<String, dynamic> next) {
    if (!mounted || (next['revision'] as int) < (s['revision'] as int)) return;
    final changed = next['revision'] != s['revision'];
    if (!changed && next['processing'] == s['processing']) return;
    final follow = !scroll.hasClients ||
        scroll.position.maxScrollExtent - scroll.offset < 120;
    final incoming = (next['messages'] as List? ?? const []);
    _optimistic.removeWhere((pending) => incoming
        .any((m) => (m as Map)['client_message_id'] == pending['client_message_id']));
    setState(() {
      final prevPhase = s['phase'] as String?;
      if (prevPhase != null && prevPhase != 'finished') {
        _lastActivePhase = prevPhase;
      }
      final nextPhase = next['phase'] as String?;
      if (nextPhase != null && nextPhase != 'finished') {
        _lastActivePhase = nextPhase;
      }
      s = next;
      _localReadAloud = null;
      networkError = null;
    });
    _syncPresenter();
    if (follow && changed) _scrollToBottom();
    _maybeOpenActionModal();
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

  Future<void> _toggleReadAloud() async {
    final next = !readAloud;
    setState(() => _localReadAloud = next);
    if (!next) _replies.interrupt();
    _syncPresenter();
    if (finished) return;
    try {
      final res = await widget.gateway.partyGameAction(
        id,
        'read_aloud',
        next ? 'true' : 'false',
        s['revision'] as int,
        'read-aloud-${DateTime.now().microsecondsSinceEpoch}',
        stage: s['action_stage'] as String? ?? '',
      );
      if (mounted) update(res);
    } catch (_) {
      // Keep local preference active even if network temporarily drops.
    }
  }

  Future<void> _sendVoice(RecordedVoice recorded) async {
    if (busy || finished) return;
    _replies.interrupt();
    final commandId = 'game-${DateTime.now().microsecondsSinceEpoch}';
    final key = 'game:$id:client:$commandId';
    final store = MessagePresentationStore.forAccount(widget.profile.id);
    try {
      await store.saveVoice(key, recorded);
    } catch (_) {}
    final optimistic = <String, dynamic>{
      'id': commandId,
      'client_message_id': commandId,
      'speaker': 'self',
      'text': recorded.text.trim(),
      if (nightMode) 'private': true,
    };
    setState(() {
      _optimistic.add(optimistic);
      busy = true;
    });
    _scrollToBottom();
    try {
      final resolved = await recorded.resolve();
      try {
        await store.finishTranscription(key, resolved);
      } catch (_) {}
      final spoken = resolved.text.trim();
      if (spoken.isEmpty) {
        if (mounted) {
          setState(() => _optimistic.remove(optimistic));
          showCenterToast(context, '没有识别到语音内容，请再试一次');
        }
        return;
      }
      final res = await widget.gateway.partyGameAction(
        id,
        'say',
        spoken,
        s['revision'] as int,
        commandId,
        stage: s['action_stage'] as String? ?? '',
      );
      retry = null;
      update(res);
    } catch (error) {
      if (mounted) {
        setState(() => _optimistic.remove(optimistic));
        showCenterToast(
            context,
            error is ApiException ? error.toString() : '语音发送未确认，请重试');
      }
      await refresh();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(String type, [String value = '']) async {
    if (busy || finished) return;
    if (type == 'say' || type == 'pause' || type == 'end') {
      _replies.interrupt();
    }
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
    _replies.suspend();
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
      _syncPresenter();
      await refresh();
    }
  }

  void identity() {
    final data = Map<String, dynamic>.from(s['private'] as Map? ?? {});
    final roleKey = data['identity'] as String?;
    final meta = _roleMeta[roleKey];
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: nightMode ? const Color(0xFF1B2033) : Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) {
          final ink = nightMode ? const Color(0xFFF2F0F7) : gameInk;
          final muted = nightMode ? const Color(0xFFA2A8C2) : gameMuted;
          final cardBg =
              nightMode ? const Color(0xFF252B42) : const Color(0xFFF9F6F8);
          final accent = meta?.color ?? gameRose;
          return SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                            child: Container(
                                width: 38,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                    color: muted.withValues(alpha: .35),
                                    borderRadius: BorderRadius.circular(4)))),
                        Row(children: [
                          Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                  color: accent.withValues(alpha: .16),
                                  borderRadius: BorderRadius.circular(14)),
                              child: Icon(meta?.icon ?? Icons.badge_outlined,
                                  color: accent, size: 24)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(meta?.name ?? '本局信息',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: ink)),
                                if (meta != null)
                                  Text(meta.camp,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: accent,
                                          fontWeight: FontWeight.w600)),
                              ])),
                        ]),
                        const SizedBox(height: 16),
                        if (data['teammates'] is List)
                          _infoTile(
                              icon: Icons.groups_rounded,
                              label: '狼人队友',
                              value: (data['teammates'] as List)
                                  .map((p) => _playerName(p as String))
                                  .join('、'),
                              bg: cardBg,
                              ink: ink,
                              muted: muted,
                              accent: accent),
                        if (data['potions'] is Map)
                          _infoTile(
                              icon: Icons.science_outlined,
                              label: '药水状态',
                              value:
                                  '解药：${data['potions']['save'] == true ? '可用' : '已用'}　毒药：${data['potions']['poison'] == true ? '可用' : '已用'}',
                              bg: cardBg,
                              ink: ink,
                              muted: muted,
                              accent: accent),
                        if (data['victim'] is String)
                          _infoTile(
                              icon: Icons.warning_amber_rounded,
                              label: '今晚袭击情报',
                              value:
                                  '今晚被袭击的是：${_playerName(data['victim'] as String)}',
                              bg: cardBg,
                              ink: ink,
                              muted: muted,
                              accent: const Color(0xFFD94A5A)),
                        if ((data['clues'] as List? ?? []).isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('私有查验记录',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: muted)),
                          const SizedBox(height: 8),
                          for (final clue in data['clues'] as List)
                            _infoTile(
                                icon: clue['wolf'] == true
                                    ? Icons.dangerous_outlined
                                    : Icons.verified_user_outlined,
                                label: '第 ${clue['day']} 夜查验',
                                value:
                                    '${_playerName(clue['target'] as String)} 是 ${clue['wolf'] == true ? '狼人' : '好人'}',
                                bg: cardBg,
                                ink: ink,
                                muted: muted,
                                accent: clue['wolf'] == true
                                    ? const Color(0xFFD94A5A)
                                    : const Color(0xFF2B8A7E)),
                        ],
                        const SizedBox(height: 10),
                        Text('仅对你本人可见，不会暴露给其他搭子。',
                            style: TextStyle(fontSize: 12, color: muted)),
                        const SizedBox(height: 16),
                        GameButton('知道了',
                            onPressed: () => Navigator.pop(context)),
                      ])));
        });
  }

  Widget _infoTile(
      {required IconData icon,
      required String label,
      required String value,
      required Color bg,
      required Color ink,
      required Color muted,
      required Color accent}) {
    return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label, style: TextStyle(fontSize: 11, color: muted)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: ink)),
              ])),
        ]));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPresenter();
      unawaited(refresh());
    } else {
      _replies.suspend();
    }
  }

  Widget controls() {
    if (_replies.busy) return const SizedBox.shrink();
    final night = nightMode;
    final ink = night ? const Color(0xFFF2F0F7) : gameInk;
    final muted = night ? const Color(0xFFA2A8C2) : gameMuted;
    final line = night ? const Color(0xFF2E3550) : gameLine;
    final surface = night ? const Color(0xFF1D2337) : const Color(0xFFFAF7FA);
    final accent = night ? const Color(0xFFA78BFA) : gameRose;
    final hasModal = _hasModalAction;
    final hasActions = !hasModal && choices.isNotEmpty;
    final isPureSpeakHint = choices.isEmpty &&
        s['actor'] == 'self' &&
        const {'speech', 'answer', 'last_words'}.contains(s['phase']);
    final hasHint = s['action_hint'] is String && !isPureSpeakHint && !hasModal;
    if (!hasModal && !hasActions && !paused && !hasHint) {
      return const SizedBox.shrink();
    }
    if (hasModal && !paused) {
      final isVote = s['phase'] == 'vote';
      final label = isVote
          ? '打开投票面板'
          : _isWitchPanel
              ? '打开女巫用药面板'
              : myIdentity == 'seer'
                  ? '选择今晚查验对象'
                  : '选择今晚袭击目标';
      return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: line))),
          child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  onPressed: busy || retry != null ? null : _openActionModal,
                  style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  icon: Icon(
                      isVote
                          ? Icons.how_to_vote_rounded
                          : Icons.nights_stay_rounded,
                      size: 18),
                  label: Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)))));
    }
    return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
            color: surface,
            border: Border(top: BorderSide(color: line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (paused)
            SizedBox(
                width: double.infinity,
                child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                        onPressed:
                            busy || retry != null ? null : () => act('resume'),
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                accent.withValues(alpha: night ? .25 : .14),
                            foregroundColor: accent,
                            shape: const StadiumBorder()),
                        child: const Text('继续游戏')))),
          if (hasHint)
            Container(
                width: double.infinity,
                margin: EdgeInsets.only(
                    top: paused ? 8 : 0, bottom: hasActions ? 4 : 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: night ? .16 : .10),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(
                      night
                          ? Icons.nights_stay_rounded
                          : s['phase'] == 'vote'
                              ? Icons.how_to_vote_outlined
                              : Icons.tips_and_updates_outlined,
                      size: 15,
                      color: accent),
                  const SizedBox(width: 7),
                  Expanded(
                      child: Text(s['action_hint'] as String,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: night ? ink : gameInk))),
                ])),
          if (hasActions)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: truth &&
                        s['phase'] == 'choose' &&
                        choices.containsKey('truth') &&
                        choices.containsKey('dare')
                    ? LayoutBuilder(builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 320 ||
                            MediaQuery.textScalerOf(context).scale(14) > 19;
                        final truthBtn = _truthChoiceCard(
                            label: choices['truth'].toString(),
                            subtitle: '走心聊点真实的',
                            icon: Icons.favorite_rounded,
                            accent: gameRose,
                            bg: const Color(0xFFFFF0F6),
                            onTap: busy || paused || retry != null
                                ? null
                                : () => act('choice', 'truth'));
                        final dareBtn = _truthChoiceCard(
                            label: choices['dare'].toString(),
                            subtitle: '来个轻松小挑战',
                            icon: Icons.auto_awesome_rounded,
                            accent: const Color(0xFF7B61FF),
                            bg: const Color(0xFFF4F0FF),
                            onTap: busy || paused || retry != null
                                ? null
                                : () => act('choice', 'dare'));
                        return narrow
                            ? Column(children: [
                                truthBtn,
                                const SizedBox(height: 8),
                                dareBtn,
                              ])
                            : Row(children: [
                                Expanded(child: truthBtn),
                                const SizedBox(width: 10),
                                Expanded(child: dareBtn),
                              ]);
                      })
                    : _targetActionPanel(
                        ink: ink,
                        muted: muted,
                        line: line,
                        accent: accent,
                        night: night)),
        ]));
  }

  bool get _isWitchPanel =>
      !truth &&
      s['phase'] == 'night' &&
      (choices.containsKey('save') ||
          choices.keys.any((k) => k.startsWith('poison:')));

  Future<void> _openActionModal() async {
    if (_sheetOpen || !_hasModalAction || !mounted) return;
    _sheetOpen = true;
    final night = nightMode;
    final isVote = s['phase'] == 'vote';
    final isWitch = _isWitchPanel;
    final snapshotChoices = Map<String, dynamic>.from(choices);
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        String? picked;
        bool showPoison = false;
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          final bg = night ? const Color(0xFF1A2034) : Colors.white;
          final cardBg =
              night ? const Color(0xFF232A42) : const Color(0xFFFAF7FA);
          final ink = night ? const Color(0xFFF2F0F7) : gameInk;
          final muted = night ? const Color(0xFF9EA5C0) : gameMuted;
          final line = night ? const Color(0xFF313958) : const Color(0xFFEEE8EE);
          final accent = isVote
              ? gameRose
              : isWitch
                  ? const Color(0xFF2FA88E)
                  : const Color(0xFFA78BFA);
          final title = isVote
              ? '第 ${s['round']} 天 · 独立投票'
              : isWitch
                  ? '女巫夜间行动'
                  : myIdentity == 'seer'
                      ? '预言家查验'
                      : '狼队夜间袭击';
          final subtitle = isVote
              ? '暗票独立选择，确认后不能修改'
              : (s['action_hint'] as String? ?? '请选择今晚的行动');
          final icon = isVote
              ? Icons.how_to_vote_rounded
              : isWitch
                  ? Icons.science_rounded
                  : myIdentity == 'seer'
                      ? Icons.visibility_rounded
                      : Icons.nights_stay_rounded;
          final victimId = (s['private'] as Map?)?['victim'] as String?;
          final victimPerson = victimId != null
              ? people.where((p) => p.id == victimId).firstOrNull
              : null;
          final victimName = victimId != null ? _playerName(victimId) : null;
          final poisons = snapshotChoices.entries
              .where((e) => e.key.startsWith('poison:'))
              .toList();
          final targets = snapshotChoices.entries
              .where((e) => e.key != 'skip' && !e.key.startsWith('poison:') && e.key != 'save')
              .toList();
          return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetCtx).height * .78),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(26)),
              border: night
                  ? const Border(top: BorderSide(color: Color(0xFF343D5E)))
                  : null,
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: muted.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: night ? .20 : .12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(icon, color: accent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: ink)),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                style: TextStyle(fontSize: 12, color: muted)),
                          ],
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: muted,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('看发言', style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    if (isWitch) ...[
                      if (victimName != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD94A5A)
                                .withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFFD94A5A)
                                    .withValues(alpha: .42)),
                          ),
                          child: Row(children: [
                            if (victimPerson != null) ...[
                              GamePortrait(victimPerson, size: 34),
                              const SizedBox(width: 10),
                            ] else ...[
                              const Icon(Icons.warning_amber_rounded,
                                  color: Color(0xFFE05A74), size: 22),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Text('今晚被袭击的是 $victimName',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFFFD5DC))),
                            ),
                          ]),
                        ),
                      if (snapshotChoices.containsKey('save')) ...[
                        _modalChoiceTile(
                          icon: Icons.healing_rounded,
                          title: victimName != null
                              ? '使用解药 · 救下 $victimName'
                              : '使用解药',
                          subtitle: '消耗 1 瓶解药，救回今晚倒牌玩家',
                          accent: const Color(0xFF2FA88E),
                          bg: const Color(0xFF1F3838),
                          onTap: () => Navigator.pop(sheetCtx, 'save'),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (poisons.isNotEmpty) ...[
                        _modalChoiceTile(
                          icon: Icons.science_rounded,
                          title: showPoison ? '收起毒药目标' : '使用毒药',
                          subtitle: '消耗 1 瓶毒药，直接令一名玩家出局',
                          accent: const Color(0xFFE05A74),
                          bg: const Color(0xFF33203A),
                          trailing: Icon(
                              showPoison
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: const Color(0xFFE05A74)),
                          onTap: () => setSheet(() => showPoison = !showPoison),
                        ),
                        if (showPoison) ...[
                          const SizedBox(height: 12),
                          _modalTargetGrid(
                            entries: [
                              for (final e in poisons)
                                MapEntry(
                                    e.key,
                                    e.value
                                        .toString()
                                        .replaceFirst('毒杀', ''))
                            ],
                            picked: picked,
                            accent: const Color(0xFFE05A74),
                            cardBg: cardBg,
                            ink: ink,
                            line: line,
                            night: night,
                            onPick: (k) => setSheet(() => picked = k),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: picked != null &&
                                    picked!.startsWith('poison:')
                                ? () => Navigator.pop(sheetCtx, picked)
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE05A74),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 46),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              picked != null && picked!.startsWith('poison:')
                                  ? '确认毒杀 ${_playerName(picked!.substring('poison:'.length))}'
                                  : '请先选择要毒杀的玩家',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                      ],
                      if (snapshotChoices.containsKey('skip'))
                        OutlinedButton(
                          onPressed: () => Navigator.pop(sheetCtx, 'skip'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: muted,
                            side: BorderSide(color: line),
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(snapshotChoices['skip'].toString(),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                    ] else ...[
                      _modalTargetGrid(
                        entries: targets,
                        picked: picked,
                        accent: accent,
                        cardBg: cardBg,
                        ink: ink,
                        line: line,
                        night: night,
                        onPick: (k) => setSheet(() => picked = k),
                      ),
                      const SizedBox(height: 18),
                      Row(children: [
                        if (snapshotChoices.containsKey('skip')) ...[
                          OutlinedButton(
                            onPressed: () => Navigator.pop(sheetCtx, 'skip'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: muted,
                              side: BorderSide(color: line),
                              minimumSize: const Size(84, 48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                            ),
                            child: Text(snapshotChoices['skip'].toString(),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: picked != null
                                ? () => Navigator.pop(sheetCtx, picked)
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                            ),
                            child: Text(
                              picked != null
                                  ? '${isVote ? '确认投给' : myIdentity == 'seer' ? '确认查验' : '确认袭击'} ${snapshotChoices[picked]}'
                                  : (isVote
                                      ? '请选择投票对象'
                                      : myIdentity == 'seer'
                                          ? '请选择查验对象'
                                          : '请选择袭击目标'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
    _sheetOpen = false;
    if (selected != null && mounted) {
      await act('choice', selected);
    }
  }

  Widget _modalChoiceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required Color bg,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: .48)),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .20),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFFB3B9D1))),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ]),
        ),
      ),
    );
  }

  Widget _modalTargetGrid({
    required List<MapEntry<String, dynamic>> entries,
    required String? picked,
    required Color accent,
    required Color cardBg,
    required Color ink,
    required Color line,
    required bool night,
    required ValueChanged<String> onPick,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
      final columns = (constraints.maxWidth < 290 || largeText) ? 2 : 3;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final entry in entries)
            Builder(builder: (_) {
              final rawId = entry.key.startsWith('poison:')
                  ? entry.key.substring('poison:'.length)
                  : entry.key;
              final person = people.where((p) => p.id == rawId).firstOrNull;
              final seat = _seatTag(rawId);
              final isSelected = picked == entry.key;
              return SizedBox(
                width: width,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onPick(entry.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent.withValues(alpha: night ? .22 : .10)
                            : cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? accent : line,
                          width: isSelected ? 1.8 : 1,
                        ),
                      ),
                      child: Column(children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (person != null)
                              GamePortrait(person, size: 48)
                            else
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.person_rounded,
                                    color: accent, size: 26),
                              ),
                            if (seat != null)
                              Positioned(
                                top: -4,
                                left: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? accent
                                        : (night
                                            ? const Color(0xFF343D5E)
                                            : const Color(0xFF3F3943)),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Text(seat,
                                      style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ),
                              ),
                            if (isSelected)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
                                  ),
                                  child: const Icon(Icons.check_rounded,
                                      size: 13, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(entry.value.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected ? accent : ink)),
                      ]),
                    ),
                  ),
                ),
              );
            }),
        ],
      );
    });
  }

  Widget _playerChoicePill({
    required String playerId,
    required String label,
    required Color accent,
    required Color bg,
    required Color textColor,
    required VoidCallback? onTap,
  }) {
    final person = people.where((p) => p.id == playerId).firstOrNull;
    final seat = _seatTag(playerId);
    return Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
                padding: EdgeInsets.fromLTRB(
                    person != null ? 5 : 12, 5, 12, 5),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withValues(alpha: .48))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (person != null) ...[
                    GamePortrait(person, size: 24),
                    const SizedBox(width: 6),
                  ],
                  if (seat != null) ...[
                    Text(seat,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent)),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textColor))),
                ]))));
  }

  Widget _targetActionPanel({
    required Color ink,
    required Color muted,
    required Color line,
    required Color accent,
    required bool night,
  }) {
    final disabled = busy || paused || retry != null;
    return ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .26),
        child: SingleChildScrollView(
            child: Wrap(spacing: 8, runSpacing: 7, children: [
          for (final option in choices.entries)
            if (option.key != 'skip' &&
                people.any((p) => p.id == option.key))
              _playerChoicePill(
                  playerId: option.key,
                  label: option.value.toString(),
                  accent: accent,
                  bg: night ? const Color(0xFF282E49) : Colors.white,
                  textColor: ink,
                  onTap: disabled ? null : () => act('choice', option.key))
            else
              ActionChip(
                  backgroundColor: option.key == 'skip'
                      ? (night
                          ? const Color(0xFF252B42)
                          : const Color(0xFFF1EEF2))
                      : (night ? const Color(0xFF2F2850) : Colors.white),
                  side: BorderSide(
                      color: option.key == 'skip'
                          ? line
                          : accent.withValues(alpha: .55)),
                  label: Text(option.value.toString(),
                      style: TextStyle(
                          color: option.key == 'skip' ? muted : ink,
                          fontWeight: option.key == 'skip'
                              ? FontWeight.w400
                              : FontWeight.w600)),
                  onPressed: disabled ? null : () => act('choice', option.key)),
          if (truth && s['actor'] == 'self' && s['phase'] == 'answer')
            ActionChip(
                avatar:
                    const Icon(Icons.refresh_rounded, size: 16, color: gameRose),
                backgroundColor: const Color(0xFFFFF2F7),
                side: BorderSide(color: gameRose.withValues(alpha: .4)),
                label: const Text('换一题',
                    style: TextStyle(
                        color: gameRose, fontWeight: FontWeight.w600)),
                onPressed: disabled ? null : () => act('change_question')),
        ])));
  }

  Widget _truthChoiceCard(
      {required String label,
      required String subtitle,
      required IconData icon,
      required Color accent,
      required Color bg,
      required VoidCallback? onTap}) {
    return Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: .32))),
                child: Row(children: [
                  Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                          color: accent.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(11)),
                      child: Icon(icon, size: 18, color: accent)),
                  const SizedBox(width: 9),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: accent)),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: gameMuted)),
                      ])),
                ]))));
  }

  Widget _truthSpotlightCard() {
    final question = s['question'] as String;
    final dare = s['kind'] == 'dare';
    final accent = dare ? const Color(0xFF7B61FF) : gameRose;
    final actor = s['actor'] as String?;
    final responder = actor != null ? _playerName(actor) : '本轮参与者';
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dare
                    ? const [Color(0xFFF6F2FF), Color(0xFFFFFAFD)]
                    : const [Color(0xFFFFF1F7), Color(0xFFFFFBFD)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: .28)),
            boxShadow: [
              BoxShadow(
                  color: accent.withValues(alpha: .08),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: accent, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      dare
                          ? Icons.auto_awesome_rounded
                          : Icons.favorite_rounded,
                      size: 11,
                      color: Colors.white),
                  const SizedBox(width: 4),
                  Text(dare ? '大冒险' : '真心话',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ])),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    actor == 'self' ? '轮到你来回应' : '轮到 $responder 回应',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: gameMuted))),
          ]),
          const SizedBox(height: 7),
          Text(question,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: gameInk)),
        ]));
  }

  Widget _truthSummaryCard() {
    final totalRounds = s['rounds'] ?? s['round'];
    return Container(
        margin: const EdgeInsets.only(top: 16, bottom: 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF2F8), Color(0xFFFFFFFF)]),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFF3DCE7)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0D9D5871),
                  blurRadius: 14,
                  offset: Offset(0, 6))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: gameRose.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.celebration_rounded,
                    color: gameRose, size: 20)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('小聚圆满结束',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: gameInk)),
                  Text('共完成 $totalRounds 轮真心话大冒险 · 聊天记录已保存',
                      style: const TextStyle(fontSize: 12, color: gameMuted)),
                ])),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final person in people)
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: gameLine)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    GamePortrait(person, size: 22),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(person.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: gameInk))),
                  ])),
          ]),
        ]));
  }

  @override
  void dispose() {
    timer?.cancel();
    _identityIntroTimer?.cancel();
    _identityIntroCtrl.dispose();
    _replies.removeListener(_onPresenterChanged);
    _replies.dispose();
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = s['phase'] as String;
    final displayPhase = (phase == 'finished' && !showFinished)
        ? (_lastActivePhase ?? (truth ? 'answer' : 'speech'))
        : phase;
    final paused = s['paused'] == true;
    final night = nightMode;
    final bg = night ? const Color(0xFF141826) : const Color(0xFFFCFBFD);
    final barBg = night ? const Color(0xFF1A1F31) : Colors.white;
    final ink = night ? const Color(0xFFF2F0F7) : gameInk;
    final muted = night ? const Color(0xFF9EA5C0) : gameMuted;
    final accent = night ? const Color(0xFFA78BFA) : gameRose;
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
    final phaseIcon = switch (displayPhase) {
      'night' => Icons.nights_stay_rounded,
      'vote' => Icons.how_to_vote_rounded,
      'finished' => Icons.flag_rounded,
      'last_words' => Icons.record_voice_over_rounded,
      _ => truth ? Icons.auto_awesome_rounded : Icons.wb_sunny_rounded,
    };
    final pillBg = night
        ? const Color(0xFF272E4A)
        : displayPhase == 'vote'
            ? const Color(0xFFFFF1E6)
            : const Color(0xFFFCEBF2);
    final pillFg = night
        ? const Color(0xFFD6CCFF)
        : displayPhase == 'vote'
            ? const Color(0xFFC25E00)
            : gameInk;
    final roleMeta = _roleMeta[myIdentity];
    final canSpeak = !finished &&
        !paused &&
        (s['can_speak'] == true ||
            truth ||
            (phase == 'speech' && (s['alive'] as List).contains('self')));
    final actorId = s['actor'] as String?;
    final highlightActor = _replies.busy
        ? _replies.activeSpeakerId
        : (_replies.activeSpeakerId ?? actorId);
    final mySpeakTurn = !finished &&
        !paused &&
        !_replies.busy &&
        choices.isEmpty &&
        actorId == 'self' &&
        const {'speech', 'answer', 'last_words'}.contains(phase);
    final visibleMessages = [..._replies.messages, ..._optimistic];
    return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
            leading: Transform.translate(
                offset: const Offset(0, 12),
                child: IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.maybePop(context),
                    icon: Icon(Icons.chevron_left_rounded,
                        size: 28, color: ink))),
            backgroundColor: barBg,
            foregroundColor: ink,
            systemOverlayStyle: night
                ? const SystemUiOverlayStyle(
                    statusBarColor: Color(0xFF1A1F31),
                    statusBarIconBrightness: Brightness.light,
                    statusBarBrightness: Brightness.dark)
                : const SystemUiOverlayStyle(
                    statusBarColor: Colors.white,
                    statusBarIconBrightness: Brightness.dark,
                    statusBarBrightness: Brightness.light),
            centerTitle: true,
            title: Transform.translate(
                offset: const Offset(0, 12),
                child: Text(truth ? '真心话小聚' : '搭子推理局',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: ink))),
            actions: [
              Transform.translate(
                  offset: const Offset(0, 12),
                  child: IconButton(
                      tooltip: readAloud ? '关闭声音' : '开启声音',
                      onPressed: _toggleReadAloud,
                      icon: Icon(
                          readAloud
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          size: 22,
                          color: readAloud ? accent : muted))),
              PopupMenuButton<String>(
                  tooltip: '游戏操作',
                  icon: Transform.translate(
                      offset: const Offset(0, 12),
                      child: Icon(Icons.more_horiz, color: ink)),
                  onSelected: (v) {
                    if (v == 'voice') {
                      startVoice();
                    } else if (v == 'read_aloud') {
                      _toggleReadAloud();
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
                        PopupMenuItem(
                            value: 'read_aloud',
                            child: Text(readAloud ? '关闭声音朗读' : '开启声音朗读')),
                        if (!finished)
                          const PopupMenuItem(
                              value: 'voice', child: Text('实时语音通话')),
                        if (!truth)
                          const PopupMenuItem(
                              value: 'identity', child: Text('我的身份与线索')),
                        if (!finished)
                          PopupMenuItem(
                              value: paused ? 'resume' : 'pause',
                              child: Text(paused ? '继续游戏' : '先停一会儿')),
                        if (!finished && s['can_advance'] == true && truth)
                          const PopupMenuItem(
                              value: 'advance', child: Text('跳过本轮')),
                        if (!finished)
                          const PopupMenuItem(value: 'end', child: Text('结束本局'))
                      ])
            ]),
        body: Stack(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            color: bg,
            child: Column(children: [
              Container(
                  width: double.infinity,
                  color: barBg,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                                color: pillBg,
                                borderRadius: BorderRadius.circular(25)),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(phaseIcon, size: 15, color: pillFg),
                                  const SizedBox(width: 6),
                                  Flexible(
                                      child: Text(
                                          truth && s['rounds'] is int
                                              ? '第 ${s['round']}/${s['rounds']} 轮 · ${paused ? '已暂停' : phases[displayPhase] ?? displayPhase}'
                                              : '第 ${s['round']} ${truth ? '轮' : displayPhase == 'night' ? '夜' : '天'} · ${paused ? '已暂停' : phases[displayPhase] ?? displayPhase}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: pillFg))),
                                ])),
                        if (!truth && roleMeta != null)
                          InkWell(
                              borderRadius: BorderRadius.circular(25),
                              onTap: identity,
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: roleMeta.color
                                          .withValues(alpha: night ? .22 : .10),
                                      border: Border.all(
                                          color: roleMeta.color
                                              .withValues(alpha: .45)),
                                      borderRadius: BorderRadius.circular(25)),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(roleMeta.icon,
                                            size: 14, color: roleMeta.color),
                                        const SizedBox(width: 5),
                                        Text(
                                            revealIdentity
                                                ? roleMeta.name
                                                : '身份牌',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: night
                                                    ? ink
                                                    : roleMeta.color)),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => setState(() =>
                                                revealIdentity =
                                                    !revealIdentity),
                                            child: Icon(
                                                revealIdentity
                                                    ? Icons.visibility_outlined
                                                    : Icons
                                                        .visibility_off_outlined,
                                                size: 14,
                                                color: muted)),
                                      ]))),
                      ])),
              Container(
                  color: barBg,
                  child: PartySeatStrip(
                      people: people,
                      hostId: s['host_id'] as String?,
                      username: widget.profile.username ?? '我',
                      userAvatarData: widget.profile.userAvatarData,
                      nightMode: night,
                      showSeatNumbers: !truth,
                      eliminatedIds: {
                        for (final p in s['people'] as List)
                          if (!(s['alive'] as List).contains(p['id']))
                            p['id'] as String
                      },
                      activeId: highlightActor)),
              if (truth &&
                  !showFinished &&
                  s['question'] is String &&
                  (s['question'] as String).trim().isNotEmpty)
                _truthSpotlightCard(),
              if (networkError != null || s['error'] != null)
                Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: gameRose.withValues(alpha: night ? .20 : .10),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: gameRose.withValues(alpha: .3))),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 16, color: gameRose),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(networkError ?? s['error'] as String,
                              style: TextStyle(
                                  color: night ? ink : gameRose,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500))),
                      if (retry != null)
                        TextButton(
                            style: TextButton.styleFrom(
                                minimumSize: const Size(0, 28),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8)),
                            onPressed: busy
                                ? null
                                : () => act(retry!.type, retry!.value),
                            child: const Text('重试',
                                style: TextStyle(fontSize: 12))),
                    ]))
              else if (retry != null)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextButton.icon(
                        onPressed:
                            busy ? null : () => act(retry!.type, retry!.value),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('重试上一次操作'))),
              Expanded(
                  child: Stack(children: [
                GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: ListView(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 52),
                        children: [
                          for (final item in visibleMessages) bubble(item),
                          if (mySpeakTurn)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Row(children: [
                                  Expanded(
                                      child: Divider(
                                          color: accent.withValues(alpha: .28),
                                          thickness: 1)),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.mic_none_rounded,
                                                size: 14, color: accent),
                                            const SizedBox(width: 4),
                                            Text(
                                                phase == 'last_words'
                                                    ? '你已出局 · 可留下遗言'
                                                    : '轮到你发言',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: accent)),
                                          ])),
                                  Expanded(
                                      child: Divider(
                                          color: accent.withValues(alpha: .28),
                                          thickness: 1)),
                                ])),
                          if (!finished &&
                              !_replies.busy &&
                              s['waiting_user'] == true)
                            Container(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                    color: accent.withValues(
                                        alpha: night ? .16 : .09),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: accent.withValues(alpha: .24))),
                                child: Row(children: [
                                  Icon(Icons.waving_hand_rounded,
                                      size: 16, color: accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(
                                          truth
                                              ? '大家在等你回应，可以直接文字或语音说说'
                                              : '大家聊得差不多了，你可以补充发言，或点击进入投票',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: night ? ink : gameInk))),
                                ])),
                          if (showFinished && s['identities'] is Map)
                            _settlementCard(
                                Map<String, dynamic>.from(
                                    s['identities'] as Map),
                                night),
                          if (showFinished && truth) _truthSummaryCard(),
                        ])),
                if (!finished && !paused && !_replies.busy)
                  Positioned(
                      right: 14,
                      bottom: 10,
                      child: Wrap(spacing: 8, children: [
                        if (truth &&
                            s['actor'] == 'self' &&
                            s['phase'] == 'answer')
                          _floatingPill(
                              icon: Icons.refresh_rounded,
                              label: '换一题',
                              accent: gameRose,
                              night: night,
                              onTap: busy || retry != null
                                  ? null
                                  : () => act('change_question')),
                        if (truth && s['waiting_user'] == true)
                          _floatingPill(
                              icon: Icons.skip_next_rounded,
                              label: '下一轮',
                              accent: gameRose,
                              night: night,
                              onTap: busy || retry != null
                                  ? null
                                  : () => act('advance')),
                        if (!truth && s['can_advance'] == true)
                          _floatingPill(
                              icon: Icons.how_to_vote_outlined,
                              label: '进入投票',
                              accent: accent,
                              night: night,
                              onTap: busy || retry != null
                                  ? null
                                  : () => act('advance')),
                      ])),
              ])),
              if (!showFinished) controls(),
              if (showFinished)
                SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                        child: GameButton('返回娱乐页',
                            onPressed: () => Navigator.pop(context)))),
              if (!showFinished)
                MessageInput(
                    enabled: canSpeak && !busy && retry == null,
                    onSend: (v) => act('say', v),
                    onVoiceSend: _sendVoice,
                    speechGateway: _speechGateway,
                    onCall: startVoice,
                    textController: input,
                    hintText: finished
                        ? '正在播报本局结果…'
                        : canSpeak
                            ? (night
                                ? '在狼队私聊中说点什么…'
                                : mySpeakTurn
                                    ? '轮到你发言，打字或按住说话…'
                                    : '说点什么吧…')
                            : '等待当前阶段完成',
                    referenceStyle: true,
                    initialVoiceMode: false,
                    partyMode: true,
                    darkSurface: night),
            ])),
          if (_showIdentityIntro && roleMeta != null)
            _buildIdentityIntroOverlay(roleMeta),
        ]));
  }

  Widget _buildIdentityIntroOverlay(
      ({String name, String camp, String tip, Color color, IconData icon}) meta) {
    final data = Map<String, dynamic>.from(s['private'] as Map? ?? {});
    final teammates = data['teammates'] is List
        ? (data['teammates'] as List)
            .map((p) => _playerName(p as String))
            .join('、')
        : null;
    final fade = CurvedAnimation(
        parent: _identityIntroCtrl,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
    final scale = Tween<double>(begin: 0.72, end: 1.0).animate(CurvedAnimation(
        parent: _identityIntroCtrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic));
    final slide =
        Tween<Offset>(begin: const Offset(0, -0.22), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _identityIntroCtrl,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic));
    return Positioned.fill(
      child: GestureDetector(
        onTap: _dismissIdentityIntro,
        child: FadeTransition(
          opacity: fade,
          child: ColoredBox(
            color: const Color(0x990D101D),
            child: Center(
              child: SlideTransition(
                position: slide,
                child: ScaleTransition(
                  scale: scale,
                  child: Container(
                    width: 278,
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1F253D), Color(0xFF15192B)],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                          color: meta.color.withValues(alpha: .65), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                            color: meta.color.withValues(alpha: .28),
                            blurRadius: 28,
                            offset: const Offset(0, 12)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('你的本局身份',
                            style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 1.4,
                                color: Color(0xFFB1B7D1))),
                        const SizedBox(height: 16),
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: .20),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: meta.color.withValues(alpha: .6),
                                width: 1.5),
                          ),
                          child: Icon(meta.icon, color: meta.color, size: 34),
                        ),
                        const SizedBox(height: 14),
                        Text(meta.name,
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: .22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(meta.camp,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: meta.color)),
                        ),
                        const SizedBox(height: 14),
                        Text(meta.tip,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.55,
                                color: Color(0xFFD2D6EA))),
                        if (teammates != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('狼人队友：$teammates',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFFB4BE))),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Text('2 秒后自动收起到顶部「身份牌」',
                            style: TextStyle(
                                fontSize: 10.5, color: Color(0xFF838BA8))),
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

  Widget _settlementCard(Map<String, dynamic> identities, bool night) {
    final winner = s['winner'] as String?;
    final goodWon = winner == 'good';
    final bannerColor =
        goodWon ? const Color(0xFF2B8A7E) : const Color(0xFFD94A5A);
    final cardBg = night ? const Color(0xFF1D2337) : Colors.white;
    final line = night ? const Color(0xFF2E3550) : gameLine;
    final ink = night ? const Color(0xFFF2F0F7) : gameInk;
    final muted = night ? const Color(0xFF9EA5C0) : gameMuted;
    return Container(
        margin: const EdgeInsets.only(top: 18, bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: line),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: night ? .25 : .04),
                  blurRadius: 14,
                  offset: const Offset(0, 6))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (winner != null)
            Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: bannerColor.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(
                      goodWon
                          ? Icons.emoji_events_rounded
                          : Icons.nights_stay_rounded,
                      color: bannerColor,
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(goodWon ? '好人阵营获胜' : '狼人阵营获胜',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: bannerColor))),
                ])),
          Text('身份揭晓',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: ink)),
          const SizedBox(height: 10),
          for (final raw in s['people'] as List) ...[
            Builder(builder: (context) {
              final person = Map<String, dynamic>.from(raw as Map);
              final pid = person['id'] as String;
              final roleKey = identities[pid] as String?;
              final meta = _roleMeta[roleKey];
              final seat = _seatTag(pid);
              final alive = (s['alive'] as List).contains(pid);
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    if (seat != null)
                      Container(
                          width: 34,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                              color: line.withValues(alpha: .7),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(seat,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: muted))),
                    Expanded(
                        child: Text(
                            '${pid == 'self' ? '${person['name']}（你）' : person['name']}${alive ? '' : ' · 出局'}',
                            style: TextStyle(fontSize: 14, color: ink))),
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                            color: (meta?.color ?? gameMuted)
                                .withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(meta?.name ?? roleKey ?? '',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: meta?.color ?? gameMuted))),
                  ]));
            }),
          ],
        ]));
  }

  Widget _systemCard(Map<String, dynamic> m) {
    final text = m['text'] as String;
    if (text.startsWith('请独立投票，确认后不能修改') ||
        text.startsWith('白天开始，每位玩家先完整发言一次')) {
      return const SizedBox.shrink();
    }
    final isPrivate = m['private'] == true || text.startsWith('查验结果：');
    final night = nightMode;
    final ink = night ? const Color(0xFFF2F0F7) : gameInk;
    final muted = night ? const Color(0xFF9EA5C0) : gameMuted;

    if (text.startsWith('投票结果：')) {
      final raw = text.substring('投票结果：'.length);
      final grouped = <String, List<String>>{};
      for (final entry in raw.split('；')) {
        final parts = entry.split('→');
        if (parts.length == 2) {
          grouped.putIfAbsent(parts[1].trim(), () => []).add(parts[0].trim());
        }
      }
      final sorted = grouped.entries.toList()
        ..sort((a, b) {
          if (a.key == '弃票') return 1;
          if (b.key == '弃票') return -1;
          return b.value.length.compareTo(a.value.length);
        });
      final cardBg = night ? const Color(0xFF1F253B) : const Color(0xFFFFFAF5);
      final border = night ? const Color(0xFF343D5E) : const Color(0xFFF4DFCA);
      return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.how_to_vote_rounded,
                  size: 16, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              Text('本轮投票结果',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
            ]),
            const SizedBox(height: 10),
            for (final entry in sorted)
              Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: entry.key == '弃票'
                                    ? muted.withValues(alpha: .15)
                                    : const Color(0xFFD97706)
                                        .withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(
                                '${entry.key} · ${entry.value.length}票',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: entry.key == '弃票'
                                        ? muted
                                        : const Color(0xFFB45309)))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(entry.value.join('、'),
                                    style: TextStyle(
                                        fontSize: 12, color: muted)))),
                      ])),
          ]));
    }

    if (isPrivate) {
      return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: const Color(0xFF2B2246),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF7B61FF).withValues(alpha: .5))),
          child: Row(children: [
            const Icon(Icons.lock_outline_rounded,
                size: 16, color: Color(0xFFC4B5FD)),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('私密线索（仅你可见）',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFC4B5FD))),
                  const SizedBox(height: 2),
                  Text(text,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFFF3F0FF))),
                ])),
          ]));
    }

    if (text.startsWith('第 ') && text.contains('夜')) {
      return Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
              color: const Color(0xFF1F2540),
              borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.nights_stay_rounded,
                size: 15, color: Color(0xFFC4B5FD)),
            const SizedBox(width: 7),
            Flexible(
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE9E4FF)))),
          ]));
    }

    if (text.startsWith('天亮了')) {
      final safe = text.contains('无人出局');
      final accent = safe ? const Color(0xFF2B8A7E) : const Color(0xFFD94A5A);
      return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: accent.withValues(alpha: night ? .20 : .10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: .32))),
          child: Row(children: [
            Icon(
                safe ? Icons.wb_sunny_rounded : Icons.campaign_rounded,
                size: 16,
                color: accent),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: night ? ink : accent))),
          ]));
    }

    if (text.startsWith('第 ') && text.contains('轮 · 轮到')) {
      return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFFEEF5), Color(0xFFF6F1FF)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: gameRose.withValues(alpha: .22))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.auto_awesome_rounded, size: 15, color: gameRose),
            const SizedBox(width: 6),
            Flexible(
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: gameInk))),
          ]));
    }

    if (text.endsWith('被投票出局。') || text.endsWith('阵营获胜。')) {
      final goodWin = text.contains('好人阵营获胜');
      final accent =
          goodWin ? const Color(0xFF2B8A7E) : const Color(0xFFD94A5A);
      return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
              color: accent.withValues(alpha: night ? .20 : .10),
              borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(
                text.endsWith('阵营获胜。')
                    ? Icons.emoji_events_rounded
                    : Icons.gavel_rounded,
                size: 15,
                color: accent),
            const SizedBox(width: 6),
            Flexible(
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: night ? ink : accent))),
          ]));
    }

    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: night
                        ? const Color(0xFF21273D)
                        : const Color(0xFFF3EFF2),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: muted)))));
  }

  Widget bubble(Map<String, dynamic> m) {
    final speaker = m['speaker'] as String?;
    if (speaker == null) return _systemCard(m);
    final self = speaker == 'self';
    final isPrivate = m['private'] == true;
    final night = nightMode;
    final person = people.where((p) => p.id == speaker).firstOrNull;
    final seat = _seatTag(speaker);
    final msgId = m['id'] as String;
    final clientKey = m['client_message_id'] as String? ?? msgId;
    final speaking = _replies.speakingId == msgId;
    final accent = night ? const Color(0xFFA78BFA) : gameRose;
    final muted = night ? const Color(0xFF9EA5C0) : gameMuted;
    final bubbleBg = isPrivate
        ? (self ? const Color(0xFF42285C) : const Color(0xFF2C2246))
        : self
            ? const Color(0xFF2E4A3E)
            : const Color(0xFF232940);
    final useGroupSurface = !isPrivate && !night;
    final textColor = useGroupSurface ? gameInk : const Color(0xFFF2F0F7);
    return LocalMessageView(
        key: ValueKey('party-msg-$clientKey'),
        account: widget.profile.id,
        messageKey: 'game:$id:client:$clientKey',
        text: m['text'] as String? ?? '',
        isUser: self,
        beforePlayback: () async => _replies.interrupt(),
        builder: (voiceBubble) {
          final innerContent = voiceBubble != null
              ? DefaultTextStyle.merge(
                  style: TextStyle(color: textColor),
                  child: IconTheme.merge(
                      data: IconThemeData(color: textColor), child: voiceBubble))
              : Text(m['text'] as String? ?? '',
                  style:
                      TextStyle(fontSize: 15, height: 1.45, color: textColor));
          final Widget bubbleBox = useGroupSurface
              ? _PartyGroupBubbleSurface(isUser: self, child: innerContent)
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                      color: bubbleBg,
                      border: Border.all(
                          color: isPrivate
                              ? const Color(0xFF7B61FF).withValues(alpha: .5)
                              : speaking
                                  ? accent.withValues(alpha: .65)
                                  : const Color(0xFF394163),
                          width: 1.2),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(self ? 18 : 6),
                        topRight: Radius.circular(self ? 6 : 18),
                        bottomLeft: const Radius.circular(18),
                        bottomRight: const Radius.circular(18),
                      )),
                  child: innerContent);
          return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment:
                      self ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    if (!self && person != null) ...[
                      GamePortrait(person, size: 40),
                      const SizedBox(width: 8)
                    ],
                    Flexible(
                        child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * .72),
                            child: Column(
                                crossAxisAlignment: self
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!self || isPrivate)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Wrap(
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 6,
                                            children: [
                                              if (!self)
                                                Text(
                                                    '${seat != null ? '$seat · ' : ''}${person?.name ?? ''}',
                                                    style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: muted)),
                                              if (speaking)
                                                SpeakingWave(color: accent),
                                              if (isPrivate)
                                                Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 1),
                                                    decoration: BoxDecoration(
                                                        color: const Color(
                                                                0xFF7B61FF)
                                                            .withValues(
                                                                alpha: .22),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8)),
                                                    child: const Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .lock_rounded,
                                                              size: 10,
                                                              color: Color(
                                                                  0xFFC4B5FD)),
                                                          SizedBox(width: 3),
                                                          Text('仅狼队可见',
                                                              style: TextStyle(
                                                                  fontSize: 10,
                                                                  color: Color(
                                                                      0xFFC4B5FD))),
                                                        ])),
                                            ])),
                                  bubbleBox,
                                ]))),
                  ]));
        });
  }
}

class _PartyGroupBubbleSurface extends StatelessWidget {
  const _PartyGroupBubbleSurface({required this.isUser, required this.child});
  final bool isUser;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (AppearanceScope.skin(context).id != 'mint') {
      return BubbleSurface(isUser: isUser, child: child);
    }
    return SageBubble(isUser: isUser, tailAtTop: true, child: child);
  }
}

Widget _floatingPill({
  required IconData icon,
  required String label,
  required Color accent,
  required bool night,
  required VoidCallback? onTap,
}) {
  return Material(
    color: (night ? const Color(0xFF232A42) : Colors.white)
        .withValues(alpha: .95),
    elevation: 4,
    shadowColor: Colors.black.withValues(alpha: night ? .35 : .10),
    shape: StadiumBorder(
      side: BorderSide(color: accent.withValues(alpha: .42)),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: accent)),
        ]),
      ),
    ),
  );
}

class _NoopSpeechGateway implements SpeechGateway {
  const _NoopSpeechGateway();
  @override
  Future<String> transcribe(Uint8List wavAudio) async => '';
}

class _GameVoiceGateway implements GroupCallGateway {
  _GameVoiceGateway(this.gateway);
  final PartyGameGateway gateway;
  @override
  Future<WebSocket> connectGroupCall(String groupId, List<String> roleIds) =>
      gateway.connectPartyVoice(groupId);
}
