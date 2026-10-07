import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/companion_reminders.dart';
import 'package:bingo/features/chat/data/companion_store.dart';
import 'package:bingo/features/chat/presentation/widgets/chat_menu_icon.dart';
import 'package:bingo/features/chat/presentation/widgets/diary_mood_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum CompanionRecordKind {
  diary('小记', ChatMenuSymbol.diary),
  promise('约定', ChatMenuSymbol.promise),
  focus('专注', ChatMenuSymbol.focus),
  sleep('入睡', ChatMenuSymbol.sleep);

  const CompanionRecordKind(this.title, this.icon);
  final String title;
  final ChatMenuSymbol icon;
}

class CompanionRecordsPage extends StatefulWidget {
  const CompanionRecordsPage(
      {required this.userId,
      this.conversationId,
      this.initialKind = CompanionRecordKind.diary,
      super.key});
  final String userId;
  final String? conversationId;
  final CompanionRecordKind initialKind;

  @override
  State<CompanionRecordsPage> createState() => _CompanionRecordsPageState();
}

class _CompanionRecordsPageState extends State<CompanionRecordsPage> {
  final _store = CompanionStore();
  Map<String, dynamic> _data = {};
  late CompanionRecordKind _kind = widget.initialKind;
  String _status = 'waiting';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final data = widget.conversationId == null
          ? await _store.list(widget.userId)
          : <String, dynamic>{
              for (final kind in CompanionRecordKind.values)
                'moments:${widget.conversationId}:${kind.name}':
                    await _store.read(widget.userId,
                        'moments:${widget.conversationId}:${kind.name}')
            };
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<({String key, Map<String, dynamic> entry, String partner})>
      get _records {
    final records =
        <({String key, Map<String, dynamic> entry, String partner})>[];
    for (final data in _data.entries) {
      if (!data.key.endsWith(':${_kind.name}') || data.value is! Map) continue;
      final value = data.value as Map;
      for (final raw in value['entries'] as List? ?? []) {
        final entry = Map<String, dynamic>.from(raw as Map);
        if (_kind == CompanionRecordKind.promise &&
            entry['status'] != _status) {
          continue;
        }
        records.add((
          key: data.key,
          entry: entry,
          partner: value['partner_name'] as String? ?? '伙伴'
        ));
      }
    }
    records.sort((first, second) => (second.entry['time'] as String? ?? '')
        .compareTo(first.entry['time'] as String? ?? ''));
    return records;
  }

  String _date(dynamic value) {
    final time = DateTime.tryParse(value?.toString() ?? '');
    if (time == null) return '';
    return '${time.year}/${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _open(
      String key, Map<String, dynamic> entry, String partner) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _RecordDetailPage(
            userId: widget.userId,
            dataKey: key,
            kind: _kind,
            entry: entry,
            partner: partner)));
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: buildMintTheme(context),
      child: DefaultTabController(
          length: CompanionRecordKind.values.length,
          initialIndex: widget.initialKind.index,
          child: Scaffold(
              backgroundColor: BingoPalette.mintBackground,
              appBar: AppBar(
                  title: const Text('陪伴记录'),
                  centerTitle: true,
                  backgroundColor: BingoPalette.mintBackground,
                  bottom: TabBar(
                      onTap: (index) => setState(
                          () => _kind = CompanionRecordKind.values[index]),
                      tabs: [
                        for (final kind in CompanionRecordKind.values)
                          Tab(text: kind.title)
                      ])),
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _failed
                      ? Center(
                          child: TextButton(
                              onPressed: _load,
                              child: const Text('记录加载失败，点击重试')))
                      : Column(children: [
                          if (_kind == CompanionRecordKind.promise)
                            Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 0),
                                child: Wrap(spacing: 8, children: [
                                  for (final status in const {
                                    'waiting': '进行中',
                                    'completed': '已完成',
                                    'skipped': '已取消'
                                  }.entries)
                                    ChoiceChip(
                                        label: Text(status.value),
                                        selected: _status == status.key,
                                        onSelected: (_) => setState(
                                            () => _status = status.key)),
                                ])),
                          Expanded(
                              child: _records.isEmpty
                                  ? Center(
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                          ChatMenuIcon(
                                              symbol: _kind.icon, size: 42),
                                          const SizedBox(height: 16),
                                          Text('还没有${_kind.title}记录'),
                                          const SizedBox(height: 8),
                                          const Text('和伙伴一起留下的小事，会收在这里',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF809589))),
                                        ]))
                                  : RefreshIndicator(
                                      onRefresh: _load,
                                      child: ListView.separated(
                                          padding: const EdgeInsets.all(20),
                                          itemCount: _records.length,
                                          separatorBuilder: (_, index) =>
                                              const SizedBox(height: 12),
                                          itemBuilder: (_, index) {
                                            final record = _records[index];
                                            return Material(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(22),
                                                clipBehavior: Clip.antiAlias,
                                                child: ListTile(
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 18,
                                                            vertical: 12),
                                                    leading: ChatMenuIcon(
                                                        symbol: _kind.icon),
                                                    title: Text(
                                                        record.entry['text']
                                                                as String? ??
                                                            '',
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                    subtitle: Text(
                                                        '${record.partner} · ${_date(record.entry['time'])}${_kind == CompanionRecordKind.diary ? ' · ${record.entry['mood'] ?? ''}' : ''}',
                                                        style: const TextStyle(
                                                            fontSize: 12)),
                                                    trailing:
                                                        const Icon(Icons.chevron_right_rounded),
                                                    onTap: () => _open(record.key, record.entry, record.partner)));
                                          }))),
                        ]))));
}

class _RecordDetailPage extends StatefulWidget {
  const _RecordDetailPage(
      {required this.userId,
      required this.dataKey,
      required this.kind,
      required this.entry,
      required this.partner});
  final String userId;
  final String dataKey;
  final CompanionRecordKind kind;
  final Map<String, dynamic> entry;
  final String partner;
  @override
  State<_RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<_RecordDetailPage> {
  late final _text =
      TextEditingController(text: widget.entry['text'] as String? ?? '');
  late String _mood = widget.entry['mood'] as String? ?? '还不错';
  late DateTime _time =
      DateTime.tryParse(widget.entry['time'] as String? ?? '') ??
          DateTime.now();
  bool _busy = false;
  bool get _editable =>
      widget.kind == CompanionRecordKind.diary ||
      (widget.kind == CompanionRecordKind.promise &&
          widget.entry['status'] == 'waiting');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    var selected = _time.isAfter(DateTime.now())
        ? _time
        : DateTime.now().add(const Duration(minutes: 5));
    await showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
            child: SizedBox(
                height: 310,
                child: Column(children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(sheet),
                            child: const Text('取消')),
                        const Text('约好一个时间'),
                        TextButton(
                            onPressed: () {
                              setState(() => _time = selected);
                              Navigator.pop(sheet);
                            },
                            child: const Text('确定')),
                      ]),
                  Expanded(
                      child: CupertinoDatePicker(
                          initialDateTime: selected,
                          minimumDate: DateTime.now(),
                          use24hFormat: true,
                          onDateTimeChanged: (value) => selected = value)),
                ]))));
  }

  Future<void> _save([String? status]) async {
    if (_busy) return;
    final content = _text.text.trim();
    if (content.isEmpty) {
      showCenterToast(context, '先写下一点内容吧');
      return;
    }
    final promise = widget.kind == CompanionRecordKind.promise;
    final nextStatus = status ?? widget.entry['status'];
    if (promise && nextStatus == 'waiting' && !_time.isAfter(DateTime.now())) {
      showCenterToast(context, '请选择未来的约定时间');
      return;
    }
    setState(() => _busy = true);
    final store = CompanionStore();
    final reminders = CompanionReminders();
    Map<String, dynamic>? original;
    try {
      final raw = await store.read(widget.userId, widget.dataKey);
      if (raw is! Map) throw StateError('记录不存在');
      final data = Map<String, dynamic>.from(raw);
      original = Map<String, dynamic>.from(data);
      final entries = (data['entries'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      final index =
          entries.indexWhere((value) => value['id'] == widget.entry['id']);
      if (index < 0) throw StateError('记录不存在');
      entries[index] = {
        ...entries[index],
        'text': content,
        if (promise) ...{'time': _time.toIso8601String(), 'status': nextStatus},
        if (!promise) 'mood': _mood
      };
      data['entries'] = entries;
      await store.write(widget.userId, widget.dataKey, data);
      if (promise) {
        if (nextStatus == 'waiting') {
          await reminders.schedule(
              id: widget.entry['id'] as String,
              title: '${widget.partner}的小约定',
              body: content,
              time: _time);
        } else {
          await reminders.cancel(widget.entry['id'] as String);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (original != null) {
        try {
          await store.write(widget.userId, widget.dataKey, original);
        } catch (_) {}
      }
      if (mounted) showCenterToast(context, '保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
          backgroundColor: BingoPalette.mintBackground,
          appBar: AppBar(
              title: Text('${widget.kind.title}详情'),
              centerTitle: true,
              backgroundColor: BingoPalette.mintBackground),
          body: ListView(padding: const EdgeInsets.all(22), children: [
            Row(children: [
              ChatMenuIcon(symbol: widget.kind.icon),
              const SizedBox(width: 12),
              Text('和${widget.partner}',
                  style: const TextStyle(fontWeight: FontWeight.w600))
            ]),
            const SizedBox(height: 22),
            if (widget.kind == CompanionRecordKind.diary)
              DiaryMoodSelector(
                  value: _mood,
                  onChanged:
                      _busy ? null : (value) => setState(() => _mood = value)),
            const SizedBox(height: 16),
            if (_editable)
              TextField(
                  controller: _text,
                  readOnly: _busy,
                  minLines: 5,
                  maxLines: null,
                  maxLength:
                      widget.kind == CompanionRecordKind.diary ? 2000 : 200,
                  decoration: const InputDecoration(counterText: ''))
            else
              Text(_text.text,
                  style: const TextStyle(fontSize: 17, height: 1.6)),
            const SizedBox(height: 16),
            if (widget.kind == CompanionRecordKind.promise)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('约定时间'),
                  subtitle: Text(
                      '${_time.year}/${_time.month}/${_time.day} ${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}'),
                  trailing: _editable
                      ? const Icon(Icons.chevron_right_rounded)
                      : null,
                  onTap: _editable && !_busy ? _pickTime : null),
            if (_busy) const LinearProgressIndicator(),
            if (_editable) ...[
              FilledButton(
                  onPressed: _busy ? null : () => _save(),
                  child: const Text('保存修改')),
              if (widget.kind == CompanionRecordKind.promise)
                TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() => _time = DateTime.now()
                                .add(const Duration(minutes: 15)));
                            _save();
                          },
                    child: const Text('晚点再说（15 分钟后）')),
              if (widget.kind == CompanionRecordKind.promise)
                Row(children: [
                  Expanded(
                      child: TextButton(
                          onPressed: _busy ? null : () => _save('completed'),
                          child: const Text('完成了'))),
                  Expanded(
                      child: TextButton(
                          onPressed: _busy ? null : () => _save('skipped'),
                          child: const Text('取消约定'))),
                ]),
            ],
            if ((widget.entry['reply'] as String? ?? '').isNotEmpty) ...[
              const Divider(height: 36),
              Text('${widget.partner}的回应'),
              const SizedBox(height: 12),
              Text(widget.entry['reply'] as String,
                  style: const TextStyle(height: 1.6)),
            ],
          ])));
}
