import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'package:bingo/features/entertainment/data/party_game_gateway.dart';
import 'package:bingo/features/entertainment/presentation/party_game_room_page.dart';
import 'package:bingo/features/entertainment/presentation/entertainment_page.dart';
import 'fixtures/party_preview_page.dart';
import 'package:bingo/features/entertainment/presentation/game_setup_page.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const profile = UserProfile(
    id: 'user',
    phone: '',
    username: '名字有点长的木木',
    assistantName: '',
    personality: '',
    role: '',
    onboardingComplete: true);
final roles = [
  for (var i = 0; i < 7; i++)
    RoleOption(
        id: 'p$i',
        name: '女朋友',
        builtin: i != 0,
        nickname: i == 0 ? '用户自己创建的很长名字的搭子' : '搭子$i')
];
final companions = roles.map(GameCompanion.fromRole).toList();

class Gateways implements RoleGateway, GroupGateway, PartyGameGateway {
  bool groupsFail = false;
  int writes = 0;
  Map<String, dynamic>? game;
  @override
  Future<List<Map<String, dynamic>>> listPartyGames() async =>
      game == null ? [] : [game!];
  @override
  Future<Map<String, dynamic>> createPartyGame(GameSetup setup) async {
    game = {
      'id': 'test-game',
      'revision': 0,
      'mode': 'truth',
      'phase': 'choose',
      'round': 1,
      'actor': 'self',
      'people': [
        ...setup.companions.map(
            (p) => {'id': p.id, 'name': p.name, 'avatar_key': p.avatarKey}),
        {'id': 'self', 'name': '我'}
      ],
      'alive': [...setup.companions.map((p) => p.id), 'self'],
      'messages': <Map<String, dynamic>>[],
      'options': {'truth': '真心话', 'dare': '大冒险'},
      'private': {},
      'paused': false,
      'can_speak': false,
      'can_advance': true
    };
    return Map.of(game!);
  }

  @override
  Future<Map<String, dynamic>> getPartyGame(String id) async => Map.of(game!);
  @override
  Future<Map<String, dynamic>> partyGameAction(
      String id, String type, String value, int revision, String commandId,
      {String stage = ''}) async {
    game!['revision'] = (game!['revision'] as int) + 1;
    if (type == 'choice') {
      game!.addAll({
        'phase': 'answer',
        'options': <String, String>{},
        'can_speak': true
      });
    }
    if (type == 'say') {
      (game!['messages'] as List)
          .add({'id': commandId, 'speaker': 'self', 'text': value});
    }
    if (type == 'pause') {
      game!['paused'] = true;
    }
    if (type == 'resume') {
      game!['paused'] = false;
    }
    return Map.of(game!);
  }

  @override
  Future<List<RoleOption>> listRoles() async => roles;
  @override
  Future<List<ChatGroup>> listGroups() async {
    if (groupsFail) throw StateError('offline');
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    writes++;
    throw StateError('Unexpected mutation: ${invocation.memberName}');
  }
}

Future<void> surface(WidgetTester tester, Widget child,
    {double width = 390, double scale = 1}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      theme: buildBingoTheme(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: child));
  await tester.pumpAndSettle();
}

void main() {
  test(
      'setup rejects duplicates and wrong player counts, protects selected list',
      () {
    for (final seats in [5, 7]) {
      expect(
          GameSetup(
                  game: CompanionGame.wolf,
                  companions: companions.take(seats - 1).toList(),
                  wolfSeats: seats)
              .validationError,
          isNull);
      expect(
          GameSetup(
                  game: CompanionGame.wolf,
                  companions: companions.take(seats - 2).toList(),
                  wolfSeats: seats)
              .validationError,
          isNotNull);
    }
    expect(
        GameSetup(
            game: CompanionGame.truth,
            companions: [companions[0], companions[0]]).validationError,
        isNotNull);
    final list = companions.take(2).toList();
    final setup = GameSetup(game: CompanionGame.truth, companions: list);
    list.clear();
    expect(setup.companions.length, 2);
    expect(
        GameSetup(
                game: CompanionGame.truth,
                companions: companions.take(6).toList())
            .validationError,
        isNotNull);
  });
  testWidgets(
      'five real navigation destinations keep the same height and map directly',
      (tester) async {
    for (final scale in [1.0, 1.4, 2.0]) {
      double? first;
      for (var selected = 0; selected < 5; selected++) {
        var destination = -1;
        await surface(
            tester,
            Scaffold(
                bottomNavigationBar: ReferenceNavigation(
                    entertainment: true,
                    selected: selected,
                    onSelected: (i) => destination = i,
                    onCreate: () => throw StateError('old create action'))),
            width: 320,
            scale: scale);
        final height = tester.getSize(find.byType(ReferenceNavigation)).height;
        first ??= height;
        expect(height, first);
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.text(['首页', '聊天', '娱乐', '社区', '我的'][i]).last);
          expect(destination, i);
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets(
      'hub uses actual custom roles, tolerates group loading failure and never writes',
      (tester) async {
    final api = Gateways()..groupsFail = true;
    await surface(
        tester,
        EntertainmentPage(
            roles: api,
            groups: api,
            profile: profile,
            onCreate: () {},
            onCreateRole: () {}),
        width: 320);
    expect(find.text('用户自己创建的很长名字的搭子'), findsOneWidget);
    await tester.tap(find.text('真心话大冒险').first);
    await tester.pumpAndSettle();
    expect(find.byType(GameSetupPage), findsOneWidget);
    final next = find.widgetWithText(FilledButton, '开始小聚 ›');
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.ensureVisible(find.text('用户自己创建的很长名字的搭子'));
    await tester.tap(find.text('用户自己创建的很长名字的搭子'));
    await tester.tap(find.text('搭子1'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.byType(PartyGameRoomPage), findsOneWidget);
    await tester.tap(find.text('真心话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我的体验发言');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('游戏操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('先停一会儿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续游戏'));
    await tester.pumpAndSettle();
    expect(find.text('我的体验发言'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('真心话小聚'), findsOneWidget);
    await tester.tap(find.text('真心话小聚'));
    await tester.pumpAndSettle();
    expect(find.text('我的体验发言'), findsOneWidget);
    expect(api.writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'private action, vote confirmation and locking do not invent a game result',
      (tester) async {
    final session = GamePreviewSession(GameSetup(
        game: CompanionGame.wolf,
        companions: companions.take(4).toList(),
        wolfSeats: 5));
    await surface(tester, GamePreviewPage(session: session, profile: profile),
        width: 320);
    await tester.tap(find.text('知道了，看看夜间行动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搭子1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认查验'));
    await tester.pumpAndSettle();
    expect(find.text('私密查验 · 结果页预览'), findsOneWidget);
    await tester.tap(find.text('看看白天讨论'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我怀疑搭子1');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(session.vote, isNull);
    await tester.tap(find.text('进入投票'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搭子1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认投票'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('再想想'));
    await tester.pumpAndSettle();
    expect(session.voteLocked, isFalse);
    await tester.tap(find.text('确认投票'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(session.voteLocked, isTrue);
    await tester.tap(find.text('搭子2'));
    await tester.pumpAndSettle();
    expect(session.vote, 'p1');
    await tester.tap(find.text('查看体验回顾'));
    await tester.pumpAndSettle();
    expect(find.text('好人阵营获胜'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('live game controls fit narrow screens and large text',
      (tester) async {
    for (final scale in [1.0, 1.4, 2.0]) {
      for (final phase in ['choose', 'answer', 'finished']) {
        final api = Gateways();
        final snapshot = await api.createPartyGame(GameSetup(
            game: CompanionGame.truth, companions: companions.take(3).toList()));
        snapshot.addAll({
          'mode': 'truth',
          'phase': phase,
          'round': 2,
          'rounds': 5,
          'actor': 'self',
          'kind': 'truth',
          'question': phase == 'choose' ? null : '最近让你偷偷开心的一件小事是什么？',
          'can_advance': phase != 'finished',
          'options': phase == 'choose'
              ? {'truth': '真心话', 'dare': '大冒险'}
              : <String, String>{},
          'messages': [
            {'id': 't1', 'speaker': null, 'text': '第 2 轮 · 轮到我'},
            {'id': 't2', 'speaker': 'p0', 'text': '最近让你偷偷开心的一件小事是什么？'},
          ],
        });
        await surface(
            tester,
            PartyGameRoomPage(
                key: ValueKey('truth-$phase-$scale'),
                gateway: api,
                initial: snapshot,
                profile: profile),
            width: 320,
            scale: scale);
        expect(tester.takeException(), isNull);
      }
      for (final phase in ['vote', 'discuss', 'night', 'finished']) {
        final api = Gateways();
        final snapshot = await api.createPartyGame(GameSetup(
            game: CompanionGame.wolf, companions: companions.take(6).toList()));
        snapshot.addAll({
          'mode': 'wolf',
          'phase': phase,
          'actor': phase == 'night' ? 'self' : 'p1',
          'can_advance': phase == 'discuss',
          'winner': phase == 'finished' ? 'good' : null,
          'identities': phase == 'finished'
              ? {
                  'self': 'seer',
                  'p0': 'wolf',
                  'p1': 'wolf',
                  'p2': 'witch',
                  'p3': 'villager',
                  'p4': 'villager',
                  'p5': 'villager',
                }
              : null,
          'private': phase == 'night'
              ? {
                  'identity': 'witch',
                  'potions': {'save': true, 'poison': true},
                  'victim': 'p0',
                  'clues': []
                }
              : {
                  'identity': 'seer',
                  'clues': [
                    {'day': 1, 'target': 'p0', 'wolf': true}
                  ]
                },
          'messages': [
            {'id': 'm1', 'speaker': null, 'text': '第 1 夜，请按自己的身份行动。'},
            {
              'id': 'm2',
              'speaker': 'p0',
              'text': '今晚刀谁？',
              'private': true,
            },
            {
              'id': 'm3',
              'speaker': null,
              'text': '查验结果：搭子1是狼人。',
              'private': true,
            },
            {'id': 'm4', 'speaker': null, 'text': '天亮了。搭子2出局。'},
            {'id': 'm5', 'speaker': 'p1', 'text': '我先说说我的判断。'},
            {
              'id': 'm6',
              'speaker': null,
              'text': '投票结果：我→搭子1；搭子1→搭子2；搭子3→搭子1；搭子4→弃票',
            },
          ],
          'options': {
            if (phase == 'night') ...{
              'skip': '不用药',
              'save': '使用解药',
              for (final p in companions.take(6)) 'poison:${p.id}': '毒杀${p.name}',
            },
            if (phase == 'vote') ...{
              for (final p in companions.take(6)) p.id: p.name,
              'skip': '弃票'
            },
          }
        });
        await surface(
            tester,
            PartyGameRoomPage(
                key: ValueKey('$phase-$scale'),
                gateway: api,
                initial: snapshot,
                profile: profile),
            width: 320,
            scale: scale);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('hub and configuration handle narrow layouts and larger text',
      (tester) async {
    for (final scale in [1.0, 1.4, 2.0]) {
      final api = Gateways();
      await surface(
          tester,
          EntertainmentPage(
              roles: api,
              groups: api,
              profile: profile,
              onCreate: () {},
              onCreateRole: () {}),
          width: 320,
          scale: scale);
      expect(tester.takeException(), isNull);
      await surface(
          tester,
          GameSetupPage(
              game: CompanionGame.wolf,
              people: companions,
              groups: [],
              profile: profile,
              onCreateRole: () {}),
          width: 320,
          scale: scale);
      expect(tester.takeException(), isNull);
    }
  });
}
