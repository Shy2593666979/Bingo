import 'package:bingo/features/entertainment/domain/game_setup.dart';
import 'fixtures/party_preview_session.dart';
import 'package:flutter_test/flutter_test.dart';

const people = [
  GameCompanion(id: 'a', name: '甜甜', avatarKey: '女朋友'),
  GameCompanion(id: 'b', name: '陈叔', avatarKey: '家长'),
  GameCompanion(id: 'c', name: '小田老师', avatarKey: '老师'),
  GameCompanion(id: 'd', name: '自建角色', avatarKey: '自建角色')
];
void main() {
  testWidgets(
      'companions open and play their own turn, then genuinely wait for the user',
      (tester) async {
    final session = GamePreviewSession(GameSetup(
        game: CompanionGame.truth, companions: people.take(3).toList()));
    addTearDown(session.dispose);
    session.activate();
    await tester.pump(const Duration(minutes: 1));
    expect(session.round, 2);
    expect(session.userTurn, isTrue);
    expect(session.awaitingChoice, isTrue);
    expect(
        session.messages
            .where((m) => m.person != null)
            .map((m) => m.person!.id)
            .toSet()
            .length,
        greaterThanOrEqualTo(2));
    expect(session.messages.any((m) => m.user), isFalse);
    final before = session.round;
    await tester.pump(const Duration(minutes: 5));
    expect(session.round, before);
    session.choose('真心话');
    session.send('我想和陈叔去看海');
    session.setComposing(true);
    await tester.pump(const Duration(minutes: 1));
    expect(session.round, 2,
        reason: 'an unfinished draft must hold the round open');
    expect(
        session.messages
            .any((m) => m.person?.id == 'b' && m.text.contains('听到你提起我')),
        isTrue);
    session.setComposing(false);
    await tester.pump(const Duration(seconds: 20));
    expect(session.round, greaterThan(2));
    expect(
        session.messages.any((m) => m.banner && m.text == '第 2 轮结束'), isTrue);
    session.suspend();
  });
  testWidgets(
      'pause, navigation suspension and disposal stop automatic conversation',
      (tester) async {
    final session = GamePreviewSession(GameSetup(
        game: CompanionGame.truth, companions: people.take(2).toList()));
    session.activate();
    await tester.pump(const Duration(seconds: 2));
    session.pause();
    final paused = session.messages.length;
    await tester.pump(const Duration(minutes: 1));
    expect(session.messages.length, paused);
    session.resume();
    await tester.pump(const Duration(seconds: 5));
    expect(session.messages.length, greaterThan(paused));
    session.suspend();
    final suspended = session.messages.length;
    await tester.pump(const Duration(minutes: 1));
    expect(session.messages.length, suspended);
    session.activate();
    await tester.pump(const Duration(seconds: 5));
    expect(session.messages.length, greaterThan(suspended));
    session.dispose();
    final disposed = session.messages.length;
    await tester.pump(const Duration(minutes: 1));
    expect(session.messages.length, disposed);
  });
  testWidgets(
      'werewolf discussion includes companion initiative but never casts a human vote',
      (tester) async {
    final session = GamePreviewSession(
        GameSetup(game: CompanionGame.wolf, companions: people, wolfSeats: 5));
    addTearDown(session.dispose);
    session.beginDay();
    session.activate();
    await tester.pump(const Duration(seconds: 30));
    expect(session.messages.where((m) => m.person != null).length, 3);
    expect(session.phase, PreviewPhase.discussion);
    expect(session.awaitingUser, isTrue);
    expect(session.vote, isNull);
    session.send('我怀疑陈叔');
    await tester.pump(const Duration(seconds: 12));
    expect(session.phase, PreviewPhase.vote);
    expect(session.vote, isNull);
    expect(session.voteLocked, isFalse);
    expect(session.messages.where((m) => m.user).single.text, '我怀疑陈叔');
  });
}
