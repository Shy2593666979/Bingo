import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/data/party_game_gateway.dart';
import 'package:bingo/features/entertainment/presentation/party_game_room_page.dart';
import 'package:bingo/features/entertainment/presentation/game_setup_page.dart';
import 'package:bingo/features/entertainment/presentation/party_home.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:flutter/material.dart';

class EntertainmentPage extends StatefulWidget {
  const EntertainmentPage(
      {required this.roles,
      required this.groups,
      required this.profile,
      required this.onCreate,
      required this.onCreateRole,
      super.key});
  final RoleGateway roles;
  final GroupGateway groups;
  final UserProfile profile;
  final VoidCallback onCreate, onCreateRole;
  @override
  State<EntertainmentPage> createState() => EntertainmentPageState();
}

class EntertainmentPageState extends State<EntertainmentPage> {
  List<GameCompanion> _people = [];
  List<ChatGroup> _groups = [];
  bool _loading = true, _failed = false, _groupsFailed = false;
  int _generation = 0;
  Map<String, dynamic>? _session;
  bool _starting = false;
  PartyGameGateway? get games => widget.roles is PartyGameGateway
      ? widget.roles as PartyGameGateway
      : null;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = _people.isEmpty;
        _failed = false;
      });
    }
    final results = await Future.wait<Object?>([
      widget.roles
          .listRoles()
          .then<Object?>((v) => v)
          .catchError((Object _) => null),
      widget.groups
          .listGroups()
          .then<Object?>((v) => v)
          .catchError((Object _) => null),
      if (games != null)
        games!
            .listPartyGames()
            .then<Object?>((v) => v)
            .catchError((Object _) => null),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() {
      if (results[0] is List<RoleOption>) {
        _people = (results[0]! as List<RoleOption>)
            .where((p) => !p.archived)
            .map(GameCompanion.fromRole)
            .toList();
      } else {
        _failed = true;
      }
      _groupsFailed = results[1] == null;
      _groups = (results[1] as List<ChatGroup>? ?? [])
          .where((g) => !g.archived)
          .toList();
      _loading = false;
      if (results.length > 2 && results[2] is List<Map<String, dynamic>>) {
        final unfinished = (results[2] as List<Map<String, dynamic>>)
            .where((v) => v['phase'] != 'finished');
        _session = unfinished.firstOrNull;
      }
    });
  }

  Future<void> _start(CompanionGame game) async {
    if (_loading || _starting) return;
    if (games == null) {
      showCenterToast(context, '游戏服务尚未连接，请更新客户端配置');
      return;
    }
    if (_failed && _people.isEmpty) {
      showCenterToast(context, '搭子读取失败，请先重试');
      return;
    }
    final setup = await Navigator.of(context).push<GameSetup>(MaterialPageRoute(
        builder: (_) => GameSetupPage(
            game: game,
            people: _people,
            groups: _groups,
            profile: widget.profile,
            groupsFailed: _groupsFailed,
            onCreateRole: widget.onCreateRole)));
    if (setup == null || !mounted) return;
    if (_session != null && _session!['phase'] != 'finished') {
      final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('开始新的一局？'),
                  content: const Text('开始新局会结束原局，聊天记录会保留。取消后可以继续原局。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('保留原局')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('重新开始'))
                  ]));
      if (replace != true || !mounted) return;
    }
    setState(() => _starting = true);
    try {
      if (_session != null && _session!['phase'] != 'finished') {
        await games!.partyGameAction(
            _session!['id'] as String,
            'end',
            '',
            _session!['revision'] as int,
            'new-game-${DateTime.now().microsecondsSinceEpoch}');
      }
      final next = await games!.createPartyGame(setup);
      if (!mounted) return;
      setState(() => _session = next);
      await _resume();
    } catch (error) {
      if (mounted) showCenterToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _resume() async {
    final session = _session;
    if (session == null || games == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => PartyGameRoomPage(
            gateway: games!, initial: session, profile: widget.profile)));
    if (mounted) {
      try {
        final next = await games!.getPartyGame(session['id'] as String);
        if (mounted) setState(() => _session = next);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => EntertainmentHome(
        people: _people,
        username: widget.profile.username?.trim().isNotEmpty == true
            ? widget.profile.username!
            : '我',
        userAvatarData: widget.profile.userAvatarData,
        loading: _loading || _starting,
        failed: _failed,
        onRefresh: refresh,
        onCreate: widget.onCreate,
        onCreateRole: widget.onCreateRole,
        onStart: _start,
        resumeTitle: _session != null && _session!['phase'] != 'finished'
            ? (_session!['mode'] == 'truth' ? '真心话小聚' : '搭子推理局')
            : null,
        resumeSubtitle:
            _session == null ? '' : '上次玩到 第 ${_session!['round']} 轮',
        onResume: _resume,
      );
}
