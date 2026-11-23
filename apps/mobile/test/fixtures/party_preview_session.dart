import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:bingo/features/entertainment/domain/game_setup.dart';

enum PreviewPhase { truth, identity, night, discussion, vote, result }

class PreviewMessage {
  const PreviewMessage(this.text,
      {this.person, this.user = false, this.banner = false});
  final String text;
  final GameCompanion? person;
  final bool user, banner;
}

class _PartyBeat {
  _PartyBeat(this.delay, this.action, {this.transition = false});
  final Duration delay;
  final VoidCallback action;
  final bool transition;
}

/// Local, disclosed sample dialogue. No model requests, real votes or memories.
/// The visible page owns activation; pending beats pause intact on navigation.
class GamePreviewSession extends ChangeNotifier {
  GamePreviewSession(this.setup)
      : phase = setup.game == CompanionGame.truth
            ? PreviewPhase.truth
            : PreviewPhase.identity {
    if (setup.validationError != null) {
      throw ArgumentError(setup.validationError);
    }
    if (setup.game == CompanionGame.truth) _opening();
  }
  final GameSetup setup;
  PreviewPhase phase;
  final messages = <PreviewMessage>[];
  final _beats = Queue<_PartyBeat>();
  Timer? _timer;
  bool _active = false, _disposed = false, _openingScene = false;
  bool paused = false,
      composing = false,
      awaitingUser = false,
      awaitingChoice = false;
  int round = 1, questionIndex = 0;
  String? kind, target, vote, activeSpeakerId;
  bool answered = false, voteLocked = false, voice = false;
  bool get finished => phase == PreviewPhase.result;
  int get _turn => (round - 1) % setup.players;
  bool get userTurn => _turn == 1;
  GameCompanion? get actorPerson =>
      userTurn ? null : setup.companions[_turn == 0 ? 0 : _turn - 1];
  String get actor => actorPerson?.name ?? '你';
  String get status => paused
      ? '先停一会儿，随时可以继续'
      : _openingScene
          ? '主持人正在带大家开场'
          : activeSpeakerId != null && activeSpeakerId != 'host'
              ? '${setup.companions.firstWhere((p) => p.id == activeSpeakerId).name}正在示例接话'
              : awaitingChoice
                  ? '轮到你 · 真心话还是大冒险？'
                  : awaitingUser
                      ? '轮到你说说，大家先听你聊'
                      : '大家一起聊 · 你也可以随时接话';
  static const questions = [
    '如果一起去旅行，你想邀请哪位搭子？',
    '今天有没有一个值得记住的小瞬间？',
    '最近有什么想慢慢学会的小事情？',
    '你最喜欢搭子怎样陪伴你？'
  ];
  static const dares = ['用三句话，夸夸一位搭子。', '给这次小聚起一个有趣的名字。', '只用五个表情，描述一下今天的心情。'];
  void activate() {
    if (_disposed) return;
    _active = true;
    _schedule();
  }

  void suspend() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  void setComposing(bool value) {
    composing = value;
  }

  void pause() {
    paused = true;
    _timer?.cancel();
    _timer = null;
    activeSpeakerId = null;
    notifyListeners();
  }

  void resume() {
    paused = false;
    _schedule();
    notifyListeners();
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    _beats.clear();
    activeSpeakerId = null;
  }

  void _queue(int milliseconds, VoidCallback action,
      {bool transition = false}) {
    _beats.add(_PartyBeat(Duration(milliseconds: milliseconds), action,
        transition: transition));
    _schedule();
  }

  void _schedule() {
    if (_disposed ||
        !_active ||
        paused ||
        _timer != null ||
        _beats.isEmpty ||
        finished) {
      return;
    }
    final beat = _beats.first;
    _timer = Timer(beat.delay, () {
      _timer = null;
      if (!_active || paused || _disposed) return;
      if (beat.transition && composing) {
        _schedule();
        return;
      }
      _beats.removeFirst();
      beat.action();
      notifyListeners();
      _schedule();
    });
  }

  void _say(String text, {GameCompanion? person}) {
    messages.add(PreviewMessage(text, person: person));
    activeSpeakerId = person?.id ?? 'host';
  }

  void _opening() {
    _openingScene = true;
    messages.add(const PreviewMessage('大家坐好，小聚准备开场', banner: true));
    _say('欢迎来坐坐。我们轮流回答，其他人可以追问、接话。不想答的题可以换，也可以跳过。');
    _queue(1600, () => _say('我想先试一轮，大家可以边听边聊。', person: setup.companions[0]));
    _queue(2200,
        () => _say('好呀，那我等着接你的话，不用一下子就说得很完整。', person: setup.companions[1]));
    _queue(1800, () {
      _openingScene = false;
      beginRound();
    }, transition: true);
  }

  void beginRound() {
    kind = null;
    answered = false;
    awaitingUser = userTurn;
    awaitingChoice = userTurn;
    messages.add(PreviewMessage('第 $round 轮开始 · 轮到$actor', banner: true));
    _say('这一轮轮到$actor。真心话还是大冒险？大家也可以接着聊。');
    if (userTurn) {
      activeSpeakerId = null;
      _queue(22000, () {
        if (awaitingUser) _say('不着急。你可以选真心话、大冒险，也可以说“先听你们聊”。');
      }, transition: true);
    } else {
      final person = actorPerson!;
      final choice = round > 1 && round.isOdd ? '大冒险' : '真心话';
      _queue(1400, () => _say('我选$choice。', person: person));
      _queue(1400, () {
        kind = choice;
        final pool = choice == '真心话' ? questions : dares;
        _say(pool[questionIndex % pool.length]);
      });
      _queue(2400, () => _say(_sampleAnswer(person), person: person));
      _queue(2000, () => _exchange(_sampleAnswer(person), from: person));
    }
  }

  String _sampleAnswer(GameCompanion person) {
    final other = setup.companions.firstWhere((p) => p.id != person.id);
    if (kind == '大冒险') {
      return switch (questionIndex % dares.length) {
        0 => '${other.name}，你愿意听人说完，也会认真回应细节。和你聊天的时候，我可以放松一点。',
        1 => '我想叫它“不赶时间的小客厅”。不用每句话都很精彩，大家能待在一起就很好。',
        _ => '🌤️ ☕ 🌿 🎧 🌙',
      };
    }
    return switch (questionIndex % 4) {
      0 => '我想邀请${other.name}去看海。不把行程排满，找个地方慢慢坐一会儿。',
      1 => '今天能和大家这样坐在一起，就是我想记住的小瞬间。',
      2 => '我想慢慢学会做一道拿手菜。下次聚会，想请你们尝尝。',
      _ => '我喜欢有人先听我说完，再说说自己的想法。不一定马上就要找到答案。',
    };
  }

  void choose(String value) {
    if (finished || !userTurn) return;
    _clear();
    kind = value;
    awaitingChoice = false;
    awaitingUser = true;
    final pool = value == '真心话' ? questions : dares;
    _say(pool[questionIndex % pool.length]);
    activeSpeakerId = null;
    notifyListeners();
  }

  void send(String value) {
    final text = value.trim();
    if (text.isEmpty || finished) return;
    composing = false;
    messages.add(PreviewMessage(text, user: true));
    final command = text.replaceAll(RegExp(r'[，。！？!?,\s]'), '');
    if (['先等等', '等等', '暂停', '先停一下'].contains(command)) {
      pause();
      return;
    }
    if (['继续', '继续游戏'].contains(command)) {
      resume();
      return;
    }
    if (paused) paused = false;
    if (['结束游戏', '结束本局'].contains(command)) {
      endExperience();
      return;
    }
    if (setup.game == CompanionGame.wolf) {
      if (phase != PreviewPhase.discussion) return;
      _clear();
      if (command == '开始投票') {
        beginVote();
        return;
      }
      _queue(
          1600,
          () =>
              _say('我听到你的判断了。可以再说说，哪一句话让你这样想吗？', person: setup.companions[0]));
      _queue(
          2800,
          () =>
              _say('先把理由听完，再各自做决定。讨论里的怀疑不算正式投票。', person: setup.companions[1]));
      _queue(2200, () => _say('这一轮讨论先收住，接下来各自确认投票对象。'));
      _queue(2200, beginVote, transition: true);
      notifyListeners();
      return;
    }
    if (['下一轮', '跳过', '先听你们聊', '我先听你们聊'].contains(command)) {
      nextRound();
      return;
    }
    if (userTurn && (command == '真心话' || command == '大冒险')) {
      choose(command);
      return;
    }
    if (command == '换一题' && userTurn) {
      questionIndex++;
      choose(kind ?? '真心话');
      return;
    }
    _clear();
    if (awaitingChoice) {
      _say('先听到你的这句话了。这轮你想选真心话，还是大冒险？');
      activeSpeakerId = null;
      notifyListeners();
      return;
    }
    answered = true;
    awaitingUser = false;
    final opening = _openingScene;
    _openingScene = false;
    _exchange(text, restartOpening: opening);
    notifyListeners();
  }

  void _exchange(String text,
      {GameCompanion? from, bool restartOpening = false}) {
    final named =
        setup.companions.where((p) => text.contains(p.name)).firstOrNull;
    final others = setup.companions.where((p) => p.id != from?.id).toList();
    final first = named != null && named.id != from?.id ? named : others.first;
    final second = setup.companions.firstWhere((p) => p.id != first.id);
    _queue(
        1300,
        () => _say(
            named?.id == first.id
                ? '听到你提起我了。一起去的话，我们可以边走边商量，不用赶着把事情定好。'
                : text.contains('海')
                    ? '我也想把时间留松一点。你更想看日出，还是坐着听海？'
                    : '你刚才说的这个小细节，我还想再听一点。为什么会想到它？',
            person: first));
    _queue(
        2300,
        () => _say(
            text.contains('海')
                ? '那就先记住这个约定吧。我喜欢大家这样一人补充一点的感觉。'
                : '我和你有一点相似的想法。先把话说出来，再慢慢听彼此的回答就好。',
            person: second));
    _queue(1800, () {
      activeSpeakerId = null;
    });
    _queue(10500, () {
      if (restartOpening) {
        beginRound();
      } else {
        _closeRound();
      }
    }, transition: true);
  }

  void _closeRound() {
    if (finished) return;
    messages.add(PreviewMessage('第 $round 轮结束', banner: true));
    _say(round >= setup.rounds
        ? '这一轮先到这里，大家都留下了一点自己的故事。'
        : '这一轮先聊到这里，接下来把话交给下一位。');
    _queue(1800, () {
      if (round >= setup.rounds) {
        _closing();
      } else {
        round++;
        questionIndex++;
        beginRound();
      }
    }, transition: true);
  }

  void nextRound() {
    if (finished) return;
    _clear();
    _openingScene = false;
    awaitingUser = false;
    awaitingChoice = false;
    _closeRound();
    notifyListeners();
  }

  void _closing() {
    _say('刚才说过的小事，下次还可以接着聊。', person: setup.companions[0]);
    _queue(2200, () => _say('好，这次不用把话说尽，留一点给下次。', person: setup.companions[1]));
    _queue(2400, endExperience, transition: true);
  }

  void beginDay() {
    _clear();
    phase = PreviewPhase.discussion;
    awaitingUser = false;
    messages.add(const PreviewMessage('第 1 天 · 白天讨论开始', banner: true));
    _say('天亮了，先把判断和理由聊清楚，之后再正式投票。');
    _queue(1500,
        () => _say('我想先听听大家的理由，不急着凭第一感觉决定。', person: setup.companions[0]));
    _queue(
        2200, () => _say('我同意先听理由，不过也不能只等别人先表态。', person: setup.companions[1]));
    _queue(2400, () => _say('那就从具体发言聊起吧。你怎么想？', person: setup.companions[2]));
    _queue(1800, () {
      awaitingUser = true;
      activeSpeakerId = null;
    });
    notifyListeners();
  }

  void beginVote() {
    _clear();
    phase = PreviewPhase.vote;
    awaitingUser = true;
    messages.add(const PreviewMessage('本轮讨论结束 · 请独立确认投票', banner: true));
    notifyListeners();
  }

  void endExperience() {
    _clear();
    phase = PreviewPhase.result;
    awaitingUser = false;
    awaitingChoice = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    suspend();
    _beats.clear();
    super.dispose();
  }
}
