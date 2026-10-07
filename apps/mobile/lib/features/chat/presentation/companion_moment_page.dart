import 'dart:async';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/companion_reminders.dart';
import 'package:bingo/features/chat/data/companion_store.dart';
import 'package:bingo/features/chat/models/moment_completion.dart';
import 'package:bingo/features/chat/models/focus_clock.dart';
import 'package:bingo/features/chat/models/sleep_session.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/chat/presentation/companion_records_page.dart';
import 'package:bingo/features/chat/presentation/widgets/chat_menu_icon.dart';
import 'package:bingo/features/chat/presentation/widgets/diary_mood_selector.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum CompanionMoment {
  focus('一起专注', ChatMenuSymbol.focus, '把这段时间，留给一件重要的小事'),
  promise('小约定', ChatMenuSymbol.promise, '和伙伴约好，一件值得期待的小事'),
  sleep('陪我入睡', ChatMenuSymbol.sleep, '不用急着回应，慢慢放松下来'),
  diary('今日小记', ChatMenuSymbol.diary, '今天的心情和小事，都可以留在这里');

  const CompanionMoment(this.title, this.icon, this.description);
  final String title;
  final ChatMenuSymbol icon;
  final String description;
}

class CompanionMomentPage extends StatefulWidget {
  const CompanionMomentPage(
      {required this.kind,
      required this.controller,
      required this.partnerName,
      required this.partnerRole,
      super.key});
  final CompanionMoment kind;
  final ChatController controller;
  final String partnerName;
  final String? partnerRole;
  @override
  State<CompanionMomentPage> createState() => _CompanionMomentPageState();
}

class _CompanionMomentPageState extends State<CompanionMomentPage>
    with WidgetsBindingObserver {
  final _store = CompanionStore();
  final _reminders = CompanionReminders();
  final _text = TextEditingController();
  Timer? _timer;
  FocusClock? _focus;
  String _activity = '学习';
  int _minutes = 25;
  String _mood = '还不错';
  String _sleepMode = '睡前故事';
  DateTime _promiseTime = DateTime.now().add(const Duration(days: 1));
  SleepSession? _sleepSession;
  String _sessionId = 'moment-${DateTime.now().microsecondsSinceEpoch}';
  bool _summarySent = false;
  bool _hasWork = false;
  bool _allowPop = false;
  bool _returning = false;
  int _diaryRecorded = 0;
  int _promiseRecorded = 0;
  Future<void>? _endTask;
  bool _loading = true;
  bool _busy = false;
  bool _loadFailed = false;
  bool _finishingFocus = false;
  final List<Map<String, dynamic>> _entries = [];
  String? _userId;
  String? _conversationId;
  String get _key => 'moments:$_conversationId:${widget.kind.name}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _userId = widget.controller.userId;
    _conversationId = widget.controller.conversationId;
    if (widget.kind == CompanionMoment.sleep) _minutes = 20;
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _load() async {
    try {
      if (_userId == null || _conversationId == null) {
        throw StateError('请先进入伙伴聊天');
      }
      final raw = await _store.read(_userId!, _key);
      if (!mounted) return;
      if (raw is Map) {
        _entries.addAll((raw['entries'] as List? ?? [])
            .map((value) => Map<String, dynamic>.from(value as Map)));
        if (raw['focus'] is Map) {
          _focus = FocusClock.fromJson(
              Map<String, dynamic>.from(raw['focus'] as Map));
          _hasWork = !_focus!.completed;
          _sessionId = raw['session_id'] as String? ?? _sessionId;
          _summarySent = raw['summary_sent'] as bool? ?? false;
        }
        _activity = raw['activity'] as String? ?? _activity;
        if (widget.kind == CompanionMoment.promise) {
          for (final entry in _entries) {
            final time = DateTime.parse(entry['time'] as String);
            if (entry['status'] == 'waiting' && time.isAfter(DateTime.now())) {
              try {
                await _reminders.schedule(
                    id: entry['id'] as String,
                    title: '${widget.partnerName}的小约定',
                    body: entry['text'] as String,
                    time: time);
              } on PlatformException catch (error) {
                if (mounted) {
                  showCenterToast(context, error.message ?? '请检查通知权限');
                }
              }
            }
          }
        }
      }
    } on PlatformException catch (error) {
      _loadFailed = true;
      if (mounted) showCenterToast(context, error.message ?? '操作未完成，请重试');
    } catch (_) {
      _loadFailed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_userId == null || _conversationId == null || _loadFailed) {
      throw StateError('本地记录暂不可用');
    }
    await _store.write(_userId!, _key, {
      'partner_name': widget.partnerName,
      'partner_role': widget.partnerRole,
      'entries': _entries,
      'focus': _focus?.toJson(),
      'activity': _activity,
      'session_id': _sessionId,
      'summary_sent': _summarySent,
    });
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (_busy || _loading || _loadFailed) return;
    setState(() => _busy = true);
    try {
      await operation();
    } on PlatformException catch (error) {
      if (mounted) showCenterToast(context, error.message ?? '操作未完成，请重试');
    } catch (_) {
      if (mounted) showCenterToast(context, '操作未完成，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tick() {
    if (!mounted || _loading) return;
    final focus = _focus;
    if (_loadFailed || focus?.deadline == null) return;
    if (!_loadFailed &&
        focus != null &&
        !focus.completed &&
        focus.deadline != null &&
        focus.remaining(DateTime.now()) == 0 &&
        !_finishingFocus) {
      _finishingFocus = true;
      focus.completed = true;
      focus.pause(DateTime.now());
      unawaited(_save()
          .then((_) =>
              _recordEnd('完成了${focus.totalSeconds ~/ 60}分钟$_activity专注。'))
          .catchError((Object _) {
        if (mounted) showCenterToast(context, '专注记录保存失败，请重试');
      }).whenComplete(() => _finishingFocus = false));
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(_sleepSession?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (widget.kind == CompanionMoment.sleep) {
      unawaited(widget.controller.stopSpeech());
    }
    _sleepSession?.dispose();
    _text.dispose();
    super.dispose();
  }

  Widget _card(List<Widget> children) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE2F0E9))),
      child: Material(
          type: MaterialType.transparency,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children)));

  Widget _choices(
          List<String> values, String value, ValueChanged<String> onChanged) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final option in values)
          ChoiceChip(
              showCheckmark: false,
              backgroundColor: BingoPalette.chatMenuSurface,
              selectedColor: BingoPalette.chatMenuSurface,
              labelStyle: TextStyle(
                  color: value == option
                      ? BingoPalette.chatMenuInk
                      : const Color(0xFF809589),
                  fontWeight:
                      value == option ? FontWeight.w600 : FontWeight.w400),
              side: BorderSide(
                  color: value == option
                      ? BingoPalette.chatMenuInk.withValues(alpha: 0.45)
                      : BingoPalette.chatMenuBorder),
              label: Text(option),
              selected: value == option,
              onSelected:
                  _busy ? null : (_) => setState(() => onChanged(option)))
      ]);

  Widget _button(String label, Future<void> Function() action,
          {IconData? icon}) =>
      Padding(
          padding: const EdgeInsets.only(top: 14),
          child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: BingoPalette.chatMenuSurface,
                      foregroundColor: BingoPalette.chatMenuInk,
                      side:
                          const BorderSide(color: BingoPalette.chatMenuBorder)),
                  onPressed:
                      _busy || _loadFailed ? null : () => _action(action),
                  icon: icon == null
                      ? ChatMenuIcon(symbol: widget.kind.icon, size: 20)
                      : Icon(icon, size: 20),
                  label: Text(label))));

  String _duration(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  String _date(DateTime value) =>
      '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  void _resetSession([String? id]) {
    _sessionId = id ?? 'moment-${DateTime.now().microsecondsSinceEpoch}';
    _summarySent = false;
    _endTask = null;
  }

  Future<void> _recordEnd(String summary) {
    if (_summarySent) return Future.value();
    return _endTask ??= _writeEnd(summary);
  }

  Future<void> _writeEnd(String summary) async {
    if (widget.controller.userId != _userId ||
        widget.controller.conversationId != _conversationId) {
      throw StateError('对话已切换');
    }
    if (mounted) setState(() => _busy = true);
    final previousEntries = List<Map<String, dynamic>>.of(_entries);
    try {
      if (widget.kind == CompanionMoment.focus ||
          widget.kind == CompanionMoment.sleep) {
        _entries.removeWhere((entry) => entry['id'] == _sessionId);
        _entries.insert(0, {
          'id': _sessionId,
          'text': summary,
          'time': DateTime.now().toIso8601String(),
        });
      }
      _summarySent = true;
      _hasWork = false;
      await _save();
      if (mounted && !_returning) {
        _returning = true;
        setState(() => _allowPop = true);
        Navigator.pop(
            context,
            MomentCompletion(
                userId: _userId!,
                conversationId: _conversationId!,
                feature: widget.kind.title,
                summary: summary,
                sessionId: _sessionId));
      }
    } catch (_) {
      _entries
        ..clear()
        ..addAll(previousEntries);
      _summarySent = false;
      _hasWork = true;
      _endTask = null;
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_returning) return;
    if (_sleepSession?.active == true) {
      await _sleepSession!.end();
      if (_sleepSession!.started && !_summarySent) {
        await _recordEnd('结束了$_sleepMode陪伴。');
      }
      _hasWork = false;
    } else if (_hasWork && !_summarySent) {
      switch (widget.kind) {
        case CompanionMoment.focus:
          final focus = _focus!;
          final elapsed = focus.totalSeconds - focus.remaining(DateTime.now());
          focus.pause(DateTime.now());
          focus.completed = true;
          await _save();
          await _recordEnd(
              '结束了$_activity专注，共${elapsed ~/ 60}分${elapsed % 60}秒。');
        case CompanionMoment.promise:
          await _recordEnd('本次保存了$_promiseRecorded个小约定。');
        case CompanionMoment.diary:
          await _recordEnd('记录了$_diaryRecorded篇今日小记，内容只保存在我的小记中。');
        case CompanionMoment.sleep:
          await _recordEnd('结束了$_sleepMode陪伴。');
      }
    }
    if (mounted && !_returning) {
      _returning = true;
      setState(() => _allowPop = true);
      Navigator.pop(context);
    }
  }

  List<Widget> _focusContent() {
    final focus = _focus;
    if (focus == null) {
      return [
        _card([
          const Text('这次想专注什么？',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          _choices(['学习', '工作', '阅读'], _activity, (value) => _activity = value),
          const SizedBox(height: 24),
          const Text('留出一段不被打扰的时间'),
          const SizedBox(height: 12),
          _choices(['25 分钟', '45 分钟', '60 分钟'], '$_minutes 分钟',
              (value) => _minutes = int.parse(value.split(' ').first)),
          _button('和${widget.partnerName}开始专注', () async {
            _resetSession();
            _hasWork = true;
            _focus = FocusClock(
                totalSeconds: _minutes * 60, remainingSeconds: _minutes * 60)
              ..resume(DateTime.now());
            await _save();
          }),
        ])
      ];
    }
    final remaining = focus.remaining(DateTime.now());
    final elapsed = focus.totalSeconds - remaining;
    return [
      _card([
        Center(
            child: Text(focus.completed ? '这一段，你做到了' : _activity,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700))),
        const SizedBox(height: 28),
        Center(
            child: SizedBox.square(
                dimension: 190,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                      child: CircularProgressIndicator(
                          value: 1 - remaining / focus.totalSeconds,
                          strokeWidth: 7,
                          backgroundColor: const Color(0xFFEAF5EF))),
                  Text(_duration(remaining),
                      style: const TextStyle(
                          fontSize: 38, fontWeight: FontWeight.w600)),
                ]))),
        const SizedBox(height: 24),
        Center(
            child: Text(focus.completed
                ? '${widget.partnerName}陪你专注了${elapsed ~/ 60}分${elapsed % 60}秒'
                : '不急，认真做完眼前这一件事')),
        if (!focus.completed)
          _button(focus.deadline == null ? '继续专注' : '暂停一下', () async {
            if (focus.deadline == null) {
              focus.resume(DateTime.now());
            } else {
              focus.pause(DateTime.now());
            }
            await _save();
          },
              icon: focus.deadline == null
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded),
        if (focus.completed)
          _button(_summarySent ? '回到聊天' : '保存结束记录', () async {
            await _recordEnd(
                '结束了$_activity专注，共${elapsed ~/ 60}分${elapsed % 60}秒。');
            await _close();
          }),
        TextButton(
            onPressed: _busy
                ? null
                : () => _action(() async {
                      if (focus.completed) {
                        _focus = null;
                        _hasWork = false;
                        await _save();
                      } else {
                        await _close();
                      }
                    }),
            child: Text(focus.completed ? '再来一段' : '结束这次专注')),
      ])
    ];
  }

  Future<void> _pickTime() async {
    var selected = _promiseTime.isAfter(DateTime.now())
        ? _promiseTime
        : DateTime.now().add(const Duration(minutes: 5));
    await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
            child: SizedBox(
                height: 310,
                child: Column(children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('取消')),
                        const Text('约好一个时间'),
                        TextButton(
                            onPressed: () {
                              setState(() => _promiseTime = selected);
                              Navigator.pop(sheetContext);
                            },
                            child: const Text('确定')),
                      ]),
                  Expanded(
                      child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.dateAndTime,
                          initialDateTime: selected,
                          minimumDate: DateTime.now(),
                          maximumDate:
                              DateTime.now().add(const Duration(days: 365)),
                          use24hFormat: true,
                          onDateTimeChanged: (value) => selected = value)),
                ]))));
  }

  Future<void> _savePromise() async {
    final content = _text.text.trim();
    if (content.isEmpty || !_promiseTime.isAfter(DateTime.now())) {
      showCenterToast(context, '写下约定，并选择未来的时间');
      return;
    }
    final id = 'moment-${DateTime.now().microsecondsSinceEpoch}';
    await _reminders.schedule(
        id: id,
        title: '${widget.partnerName}的小约定',
        body: content,
        time: _promiseTime);
    final entry = {
      'id': id,
      'text': content,
      'time': _promiseTime.toIso8601String(),
      'status': 'waiting'
    };
    final previous = List<Map<String, dynamic>>.of(_entries);
    _entries.removeWhere((value) => value['id'] == id);
    _entries.insert(0, entry);
    try {
      await _save();
    } catch (_) {
      _entries
        ..clear()
        ..addAll(previous);
      await _reminders.cancel(id);
      for (final old in previous.where(
          (value) => value['id'] == id && value['status'] == 'waiting')) {
        final time = DateTime.parse(old['time'] as String);
        if (time.isAfter(DateTime.now())) {
          await _reminders.schedule(
              id: id,
              title: '${widget.partnerName}的小约定',
              body: old['text'] as String,
              time: time);
        }
      }
      rethrow;
    }
    _text.clear();
    if (_summarySent) {
      _resetSession();
      _promiseRecorded = 0;
    }
    _hasWork = true;
    _promiseRecorded++;
    await _recordEnd('保存了一个小约定，到时间会提醒我。');
  }

  List<Widget> _promiseContent() => [
        _card([
          Text('想和${widget.partnerName}约好什么？',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          TextField(
              controller: _text,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: '明晚一起散步十分钟', counterText: '')),
          const SizedBox(height: 12),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('约定时间'),
              subtitle: Text(_date(_promiseTime)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _busy ? null : _pickTime),
          _button('存下这个小约定', _savePromise),
        ]),
      ];

  Future<void> _startSleep() async {
    final previous = _sleepSession;
    if (previous?.active == true) {
      if (previous!.paused) previous.resume();
      return;
    }
    final gateway = widget.controller.momentGateway;
    if (gateway == null || _conversationId == null) {
      throw StateError('陪伴功能暂不可用');
    }
    previous?.dispose();
    _resetSession();
    await widget.controller.stopSpeech();
    _hasWork = true;
    _sleepSession = SleepSession(
        gateway: gateway,
        conversationId: _conversationId!,
        mode: _sleepMode == '睡前故事'
            ? 'story'
            : _sleepMode == '轻声聊聊'
                ? 'comfort'
                : 'quiet',
        minutes: _minutes,
        onEnded: (automatic, seconds) => _recordEnd(
            '${automatic ? '定时结束' : '结束了'}$_sleepMode陪伴，共${seconds ~/ 60}分${seconds % 60}秒。'))
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..start();
  }

  List<Widget> _sleepContent() {
    final sleep = _sleepSession;
    final locked = sleep?.active == true;
    return [
      _card([
        Center(child: AssistantAvatar(role: widget.partnerRole, size: 82)),
        const SizedBox(height: 14),
        Center(
            child: Text('${widget.partnerName}陪你慢慢放松',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700))),
        const SizedBox(height: 24),
        if (!locked) ...[
          _choices(['睡前故事', '轻声聊聊', '安静陪伴'], _sleepMode,
              (value) => _sleepMode = value),
          const SizedBox(height: 24),
          const Text('多久后结束陪伴'),
          const SizedBox(height: 12),
          _choices(['10 分钟', '20 分钟', '30 分钟'], '$_minutes 分钟',
              (value) => _minutes = int.parse(value.split(' ').first)),
        ] else ...[
          Center(
              child: Text(
                  '$_sleepMode · ${sleep!.paused ? '已暂停' : sleep.loading ? '正在准备声音' : '陪伴中'}')),
          const SizedBox(height: 20),
          Center(
              child: Text(_duration(sleep.remainingSeconds),
                  style: const TextStyle(
                      fontSize: 36, fontWeight: FontWeight.w600))),
          const SizedBox(height: 12),
          const Center(
              child: Text('故事会自然接着讲，无需回复',
                  style: TextStyle(fontSize: 12, color: Color(0xFF809589)))),
        ],
        if (sleep?.loading == true)
          const Padding(
              padding: EdgeInsets.only(top: 18),
              child: LinearProgressIndicator()),
        if (!locked || sleep!.paused)
          _button(locked ? '继续陪伴' : '开始陪伴', _startSleep),
        if (locked && !sleep!.paused)
          TextButton.icon(
              onPressed: sleep.pause,
              icon: const Icon(Icons.pause_rounded),
              label: const Text('暂停陪伴')),
        TextButton(
            onPressed: _busy ? null : () => _action(_close),
            child: const Text('今晚就到这里，晚安')),
        if (sleep?.error != null)
          Text(sleep!.error!, style: const TextStyle(color: Colors.red)),
        if (_summarySent) const Center(child: Text('本次陪伴已结束，晚安。')),
      ])
    ];
  }

  Future<void> _saveDiary() async {
    final content = _text.text.trim();
    if (content.isEmpty) {
      showCenterToast(context, '写下一件今天的小事吧');
      return;
    }
    final entry = <String, dynamic>{
      'id': 'diary-${DateTime.now().microsecondsSinceEpoch}',
      'text': content,
      'mood': _mood,
      'time': DateTime.now().toIso8601String(),
      'reply': ''
    };
    _entries.insert(0, entry);
    try {
      await _save();
    } catch (_) {
      _entries.remove(entry);
      rethrow;
    }
    _text.clear();
    _resetSession(entry['id'] as String);
    _hasWork = true;
    _diaryRecorded++;
    await _recordEnd('记录了一篇今日小记，今天的心情是$_mood。');
  }

  List<Widget> _diaryContent() => [
        _card([
          const Text('今天，有什么想记住的？',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          DiaryMoodSelector(
              value: _mood,
              onChanged:
                  _busy ? null : (value) => setState(() => _mood = value)),
          const SizedBox(height: 16),
          TextField(
              controller: _text,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                  hintText: '一件小事，一点心情，都值得被记住', counterText: '')),
          _button('保存今日小记', _saveDiary),
        ]),
      ];

  Future<void> _openRecords() async {
    if (_userId == null || _busy || _loading || _loadFailed) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CompanionRecordsPage(
            userId: _userId!,
            conversationId: _conversationId,
            initialKind: CompanionRecordKind.values.byName(widget.kind.name))));
    if (!mounted) return;
    try {
      final raw = await _store.read(_userId!, _key);
      if (!mounted || raw is! Map) return;
      setState(() {
        _entries
          ..clear()
          ..addAll((raw['entries'] as List? ?? [])
              .map((value) => Map<String, dynamic>.from(value as Map)));
      });
    } catch (_) {
      _loadFailed = true;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: buildMintTheme(context),
      child: PopScope(
          canPop: _allowPop || (!_hasWork && !_busy),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && !_busy) unawaited(_action(_close));
          },
          child: Scaffold(
              backgroundColor: BingoPalette.mintBackground,
              appBar: AppBar(
                  leading: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: _busy ? null : () => _action(_close)),
                  backgroundColor: BingoPalette.mintBackground,
                  title: Text(widget.kind.title),
                  centerTitle: true,
                  actions: [
                    TextButton(
                        onPressed: _busy || _loading || _loadFailed || _hasWork
                            ? null
                            : _openRecords,
                        child: const Text('记录'))
                  ]),
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadFailed
                      ? const Center(child: Text('本地记录暂不可用，请返回后重试'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                          children: [
                              Row(children: [
                                AssistantAvatar(
                                    role: widget.partnerRole, size: 42),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text('和${widget.partnerName}',
                                          style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(widget.kind.description,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF71817D))),
                                    ]))
                              ]),
                              const SizedBox(height: 22),
                              if (_busy)
                                const Padding(
                                    padding: EdgeInsets.only(bottom: 14),
                                    child: LinearProgressIndicator()),
                              ...switch (widget.kind) {
                                CompanionMoment.focus => _focusContent(),
                                CompanionMoment.promise => _promiseContent(),
                                CompanionMoment.sleep => _sleepContent(),
                                CompanionMoment.diary => _diaryContent(),
                              },
                            ]))));
}
