import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/core/design/chat_scene.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:bingo/features/stickers/sticker.dart';
import 'package:bingo/features/stickers/sticker_widgets.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:bingo/features/group_chat/presentation/mention_editing_controller.dart';
import 'package:bingo/core/design/bingo_icon.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/presentation/widgets/message_input.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/features/group_chat/presentation/group_controller.dart';
import 'package:bingo/features/group_chat/presentation/group_info_page.dart';
import 'package:bingo/features/group_chat/presentation/widgets/chat_quote_card.dart';
import 'package:bingo/features/group_chat/presentation/group_reply_presenter.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/group_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:bingo/shared/widgets/speaking_wave.dart';
import 'package:flutter/material.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:bingo/features/chat/presentation/location_picker_page.dart';
import 'package:bingo/features/chat/presentation/widgets/location_card.dart';
import 'package:bingo/features/group_chat/presentation/group_call_page.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage(
      {required this.groupId,
      required this.gateway,
      required this.roles,
      required this.speech,
      this.userAvatarData,
      this.appearanceStore,
      super.key});
  final String groupId;
  final GroupGateway gateway;
  final RoleGateway roles;
  final SpeechGateway speech;
  final String? userAvatarData;
  final AppearanceStore? appearanceStore;
  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage>
    with WidgetsBindingObserver {
  late final _chat = GroupController(widget.gateway, widget.groupId);
  final _scroll = ScrollController();
  final _input = MentionEditingController();
  final _messageKeys = <String, GlobalKey>{};
  GroupChatMessage? _replyDraft;
  String? _spotlight;
  bool _locating = false;
  bool _calling = false;
  int? _mentionStart;
  String _mentionQuery = '';
  bool _forceBottom = true;
  int _highestSeenSeq = 0, _newMessageCount = 0;
  late final _replies = GroupReplyPresenter(
      gateway: widget.gateway,
      groupId: widget.groupId,
      onError: () {
        if (mounted) showCenterToast(context, '语音暂时不可用，文字回复不受影响');
      });

  @override
  void initState() {
    super.initState();
    unawaited(ChatScene.setNativeChrome(true));
    WidgetsBinding.instance.addObserver(this);
    _chat.readLimit = () => _replies.readThrough;
    _replies.addListener(_presented);
    _chat.addListener(_changed);
    if (widget.gateway case final WelcomeRefreshGateway welcome) {
      welcome.welcomeRefresh.addListener(_refreshWelcome);
    }
    widget.appearanceStore?.addListener(_changed);
    _input.addListener(_typed);
    _scroll.addListener(_readVisibleMessages);
    unawaited(_chat.load());
  }

  @override
  void dispose() {
    if (widget.gateway case final WelcomeRefreshGateway welcome) {
      welcome.welcomeRefresh.removeListener(_refreshWelcome);
    }
    _replies.removeListener(_presented);
    _replies.dispose();
    unawaited(ChatScene.setNativeChrome(false));
    WidgetsBinding.instance.removeObserver(this);
    _chat.removeListener(_changed);
    widget.appearanceStore?.removeListener(_changed);
    _chat.dispose();
    _scroll.removeListener(_readVisibleMessages);
    _scroll.dispose();
    _input.removeListener(_typed);
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _replies.suspend(historyOnResume: true);
    }
    _chat.readEnabled = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) unawaited(_chat.load());
  }

  void _readVisibleMessages() {
    if (_newMessageCount > 0 &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 40) {
      setState(() => _newMessageCount = 0);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!_chat.loading && _chat.group != null) {
      _replies.update(_chat.messages,
          sound: _chat.group!.readAloud,
          welcomeReadThrough: _chat.group!.lastReadSeq,
          enabled: !_calling && _chat.readEnabled);
    } else {
      setState(() {});
    }
  }

  void _refreshWelcome() {
    if (mounted && !_chat.busy) unawaited(_chat.load());
  }

  void _presented() {
    if (!mounted) return;
    unawaited(_chat.markRead());
    final nearBottom =
        !_scroll.hasClients || _scroll.position.extentAfter < 180;
    if (!_chat.loading) {
      if (!_forceBottom && !nearBottom && !_locating) {
        _newMessageCount += _replies.messages
            .where((m) => m.seq > _highestSeenSeq && m.type == 'assistant')
            .length;
      }
      for (final m in _replies.messages) {
        if (m.seq > _highestSeenSeq) _highestSeenSeq = m.seq;
      }
      if (nearBottom) _newMessageCount = 0;
    }
    setState(() {});
    if (!_locating && (_forceBottom || nearBottom)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          if (_forceBottom) {
            _forceBottom = false;
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scroll.hasClients) {
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
              }
            });
            return;
          }
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut);
        }
      });
    }
  }

  void _typed() {
    if (!mounted) return;
    final cursor = _input.selection.baseOffset;
    final prefix = cursor < 0
        ? ''
        : _input.text.substring(0, cursor.clamp(0, _input.text.length));
    final match = RegExp(r'@([^\s@]*)$').firstMatch(prefix);
    setState(() {
      _mentionStart = (_chat.group?.mentionsEnabled == true &&
              match != null &&
              !_input.containsCursor(cursor))
          ? prefix.lastIndexOf('@')
          : null;
      _mentionQuery = match?.group(1) ?? '';
    });
  }

  void _selectMention(GroupPerson? person) {
    final start = _mentionStart;
    if (start == null) return;
    final end = _input.selection.baseOffset.clamp(start, _input.text.length);
    _input.insertMention(
        start, end, person?.id ?? 'all', person?.name ?? '全部搭子',
        all: person == null);
  }

  void _send(String text) {
    _replies.interrupt(runId: _chat.runId);
    _forceBottom = true;
    final draftMatches = text == _input.text.trim();
    final ids = draftMatches ? _input.roleIds : <String>[];
    final all = draftMatches && _input.mentionAll;
    final quoteId = _replyDraft?.id;
    unawaited(_chat
        .send(text, ids, mentionAll: all, replyToMessageId: quoteId)
        .then((sent) {
      if (sent && mounted && _replyDraft?.id == quoteId) {
        setState(() => _replyDraft = null);
      }
    }));
  }

  Future<void> _retry(String id) async {
    _replies.interrupt(runId: _chat.runId);
    await _chat.retry(id);
  }

  Future<void> _cancelRun() async {
    _replies.interrupt(runId: _chat.runId);
    await _chat.cancel();
  }

  Future<void> _locate(String id) async {
    _locating = true;
    _forceBottom = false;
    try {
      if (!await _chat.locate(id) || !mounted) {
        if (mounted) showCenterToast(context, '原消息已不可用');
        return;
      }
      setState(() => _spotlight = id);
      _replies.revealHistory(id);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final target = _messageKeys[id]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(target,
            alignment: .25, duration: const Duration(milliseconds: 320));
      }
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (mounted) setState(() => _spotlight = null);
    } catch (_) {
      if (mounted) showCenterToast(context, '原消息暂时无法加载');
    } finally {
      _locating = false;
    }
  }

  Future<void> _messageActions(GroupChatMessage message) async {
    final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (message.status == 'completed' && message.content.isNotEmpty)
                ListTile(
                    leading: const Icon(Icons.reply_rounded),
                    title: const Text('引用回复'),
                    onTap: () => Navigator.pop(context, 'reply')),
              ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('复制'),
                  onTap: () => Navigator.pop(context, 'copy')),
            ])));
    if (!mounted) return;
    if (action == 'reply') setState(() => _replyDraft = message);
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: _preview(message.content)));
      if (mounted) showCenterToast(context, '已复制');
    }
  }

  String _preview(String text) {
    final sticker = ChatSticker.parse(text);
    return sticker == null ? text : '[表情：${sticker.label}]';
  }

  String _senderName(GroupChatMessage message) {
    return _chat.group?.senderNameFor(message) ?? message.name;
  }

  Widget _quoteCard(GroupChatMessage message) {
    final quote = message.replyTo;
    final source =
        _replies.messages.where((m) => m.id == message.replyToId).firstOrNull;
    final unavailable =
        quote?['unavailable'] == true || (quote == null && source == null);
    final createdAt =
        DateTime.tryParse(quote?['created_at'] as String? ?? '') ??
            source?.createdAt;
    return ChatQuoteCard(
        sender: source != null
            ? _senderName(source)
            : quote?['sender_name'] as String? ?? '群成员',
        content: source != null && ChatSticker.parse(source.content) != null
            ? _preview(source.content)
            : quote?['content'] as String? ?? source?.content ?? '',
        isUser: message.type == 'user',
        createdAt: createdAt,
        unavailable: unavailable,
        onTap: unavailable ? null : () => _locate(message.replyToId!));
  }

  String _displayContent(GroupChatMessage message) {
    final group = _chat.group;
    var text = message.content;
    if (group != null &&
        message.type == 'assistant' &&
        message.mentionTargets.any((target) =>
            target['type'] == 'user' && target['id'] == group.humanId)) {
      final name = group.humanName;
      final alias = RegExp('@(?:我|${RegExp.escape(group.humanId)})'
          r'(?=$|[\s，,。.!！？?：:、~～…]|你|您|先|来|接|说|回|帮|给|请)');
      text = text.replaceAllMapped(alias, (_) => '@$name');
      if (!text.contains('@$name') &&
          !(message.status == 'streaming' &&
              text.startsWith('@') &&
              '@$name'.startsWith(text))) {
        text = '@$name $text';
      }
    }
    return text.isEmpty ? '…' : text;
  }

  TextSpan _contentSpan(GroupChatMessage message) {
    final labels = <String>{
      if (message.mentionAll) ...['全部搭子', '全体搭子'],
      for (final p in _chat.group?.members ?? <GroupPerson>[])
        if (message.mentions.contains(p.id) ||
            message.mentionTargets
                .any((t) => t['type'] == 'role' && t['id'] == p.id))
          p.name,
      if (message.mentionTargets
          .any((t) => t['type'] == 'user' && t['id'] == _chat.group?.humanId))
        _chat.group?.humanName ?? '我',
    };
    final text = _displayContent(message);
    if (labels.isEmpty) return TextSpan(text: text);
    final sorted = labels.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final pattern = RegExp(sorted.map((s) => '@${RegExp.escape(s)}').join('|'));
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
      spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(
              color: BingoPalette.primaryText, fontWeight: FontWeight.w600)));
      cursor = match.end;
    }
    spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(children: spans);
  }

  Future<void> _info() async {
    if (_chat.group == null) return;
    _replies.suspend();
    _chat.readEnabled = false;
    final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => GroupInfoPage(
            group: _chat.group!,
            gateway: widget.gateway,
            roles: widget.roles,
            userAvatarData: widget.userAvatarData,
            appearanceStore: widget.appearanceStore)));
    if (!mounted) return;
    if (deleted == true) {
      Navigator.pop(context);
      return;
    }
    _chat.readEnabled = true;
    await _chat.load();
  }

  Future<void> _call() async {
    final group = _chat.group;
    final gateway = widget.gateway;
    if (group == null || _calling) return;
    if (gateway is! GroupCallGateway) {
      showCenterToast(context, '当前服务不支持群聊电话');
      return;
    }
    final members = await Navigator.push<List<GroupPerson>>(context,
        MaterialPageRoute(builder: (_) => GroupCallPickerPage(group: group)));
    if (!mounted || members == null || members.isEmpty) return;
    _calling = true;
    _chat.readEnabled = false;
    _replies.interrupt(runId: _chat.runId);
    _replies.suspend(historyOnResume: true);
    try {
      if (_chat.busy) await _cancelRun();
      if (!mounted) return;
      await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) => GroupCallPage(
                  group: group,
                  members: members,
                  gateway: gateway as GroupCallGateway,
                  userAvatarData: widget.userAvatarData)));
    } catch (_) {
      if (mounted) showCenterToast(context, '无法发起通话，请重试');
    } finally {
      _calling = false;
      _chat.readEnabled = true;
      if (mounted) await _chat.load();
    }
  }

  Future<void> _image(String method) async {
    try {
      final result = await const MethodChannel('bingo/device_tools')
          .invokeMapMethod<Object?, Object?>(method);
      if (!mounted || result == null) return;
      final bytes = result['bytes'] as Uint8List?;
      if (bytes == null || bytes.isEmpty) return;
      if (bytes.length > 5000000) {
        showCenterToast(context, '图片不能超过 5 MB');
        return;
      }
      _replies.interrupt(runId: _chat.runId);
      await _chat.send('[图片]', [], media: {
        'images': [
          {
            'mime_type': result['mime_type'] ?? 'image/jpeg',
            'data': base64Encode(bytes)
          }
        ]
      });
    } on PlatformException catch (error) {
      if (mounted) showCenterToast(context, error.message ?? '无法读取图片');
    }
  }

  Future<void> _location() async {
    final gateway = widget.gateway;
    if (gateway is! LocationGateway || _chat.group == null) return;
    final location = await Navigator.push<ChatLocation>(
        context,
        MaterialPageRoute(
            builder: (_) => LocationPickerPage(
                gateway: gateway as LocationGateway,
                accessToken: gateway is GroupMediaGateway
                    ? (gateway as GroupMediaGateway).groupMediaToken
                    : null,
                userId: _chat.group!.humanId)));
    if (mounted && location != null) {
      _replies.interrupt(runId: _chat.runId);
      await _chat.send('[位置] ${location.name}', [],
          media: {'location': location.toJson()});
    }
  }

  Widget _attachment(GroupChatMessage message) {
    final attachment = message.attachment!;
    if (attachment['type'] == 'location') {
      final location = ChatLocation.fromJson(
          Map<String, dynamic>.from(attachment['location'] as Map));
      final gateway = widget.gateway;
      return LocationCard(
          location: location,
          isUser: true,
          mapUrl: gateway is LocationGateway
              ? (gateway as LocationGateway).locationMapUrl(location)
              : null,
          accessToken: gateway is GroupMediaGateway
              ? (gateway as GroupMediaGateway).groupMediaToken
              : null);
    }
    final gateway = widget.gateway;
    final local = attachment['local_data'] as String?;
    Widget image;
    if (local != null) {
      image = Image.memory(base64Decode(local), fit: BoxFit.contain);
    } else if (gateway is GroupMediaGateway) {
      final media = gateway as GroupMediaGateway;
      image = Image.network(media.groupImageUrl(widget.groupId, message.id),
          headers: {
            if (media.groupMediaToken != null)
              'Authorization': 'Bearer ${media.groupMediaToken}'
          },
          fit: BoxFit.contain,
          errorBuilder: (_, error, trace) => const SizedBox(
              height: 90, child: Center(child: Text('图片暂时不可用'))));
    } else {
      image = const Text('[图片]');
    }
    return GestureDetector(
        onTap: () => showDialog<void>(
            context: context,
            builder: (context) =>
                Dialog(child: InteractiveViewer(child: image))),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 220, maxWidth: 240),
                child: image)));
  }

  @override
  Widget build(BuildContext context) {
    final group = _chat.group;
    final appearance =
        widget.appearanceStore?.effective('group:${widget.groupId}') ??
            const ChatAppearance();
    return AppearanceScope(
        value: appearance,
        child: Scaffold(
            backgroundColor: ChatScene.ivory,
            body: ChatWallpaper(
                value: appearance,
                child: SafeArea(
                    bottom: false,
                    child: Column(children: [
                      ChatGlass(
                          child: Container(
                              padding: const EdgeInsets.fromLTRB(6, 5, 12, 10),
                              child: Row(children: [
                                IconButton(
                                    tooltip: '返回',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.chevron_left_rounded,
                                        size: 29, color: ChatScene.ink)),
                                GroupAvatar(
                                    members: group?.activeMembers ?? [],
                                    cover: group?.cover ?? 'garden',
                                    size: 44),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Row(children: [
                                  Flexible(
                                      child: Text(group?.name ?? '群聊',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                              color: ChatScene.ink))),
                                  Text(' (${group?.activeMembers.length ?? 0})',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: ChatScene.ink))
                                ])),
                                if (_chat.busy || _replies.busy)
                                  IconButton(
                                      tooltip: '停止本轮回复',
                                      onPressed: _cancelRun,
                                      icon: const Icon(
                                          Icons.stop_circle_outlined,
                                          size: 21,
                                          color: ChatScene.muted)),
                                IconButton(
                                    tooltip: '群聊信息',
                                    onPressed: _info,
                                    icon: const Icon(Icons.more_horiz_rounded,
                                        color: ChatScene.ink))
                              ]))),
                      if (_chat.error != null)
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 5),
                            color: Colors.white.withValues(alpha: .65),
                            child: Row(children: [
                              Expanded(
                                  child: Text(_chat.error!,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: ChatScene.muted))),
                              TextButton(
                                  onPressed:
                                      _chat.canRetry ? _chat.retry : _chat.load,
                                  child: const Text('重试'))
                            ])),
                      Expanded(
                        child: Stack(
                          key: const ValueKey('group-message-viewport'),
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(24)),
                                child: ColoredBox(
                                    color: Colors.transparent,
                                    child: _chat.loading
                                        ? const Center(
                                            child: CircularProgressIndicator())
                                        : _replies.messages.isEmpty
                                            ? Center(
                                                child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                    const BingoIcon(
                                                        BingoSymbol.chat,
                                                        size: 36,
                                                        color: ChatScene.accent,
                                                        selected: true),
                                                    const SizedBox(height: 12),
                                                    Text(
                                                        '${group?.name ?? '搭子们'}已经准备好啦',
                                                        style: const TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                    const SizedBox(height: 8),
                                                    const Text(
                                                        '聊聊今天的生活，或用 @ 指定搭子回应',
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            color: ChatScene
                                                                .muted))
                                                  ]))
                                            : SingleChildScrollView(
                                                controller: _scroll,
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        12, 10, 12, 14),
                                                child: Column(children: [
                                                  if (_chat.more)
                                                    TextButton(
                                                        onPressed: () async {
                                                          try {
                                                            await _chat.older();
                                                          } catch (_) {
                                                            if (mounted) {
                                                              showCenterToast(
                                                                  this.context,
                                                                  '历史消息加载失败');
                                                            }
                                                          }
                                                        },
                                                        child: const Text(
                                                            '查看更早消息')),
                                                  for (final (index, message)
                                                      in _replies
                                                          .messages.indexed)
                                                    KeyedSubtree(
                                                        key: _messageKeys
                                                            .putIfAbsent(
                                                                message.id,
                                                                GlobalKey.new),
                                                        child: _message(message,
                                                            previous: index == 0
                                                                ? null
                                                                : _replies
                                                                        .messages[
                                                                    index -
                                                                        1])),
                                                ])))),
                            if (_newMessageCount > 0)
                              Positioned(
                                right: 12,
                                bottom: 8,
                                child: TextButton.icon(
                                  key: const ValueKey('group-new-messages'),
                                  onPressed: () {
                                    setState(() {
                                      _newMessageCount = 0;
                                      _forceBottom = true;
                                    });
                                    _changed();
                                  },
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: BingoPalette.primaryText,
                                  ),
                                  icon: const Icon(Icons.arrow_downward_rounded,
                                      size: 14),
                                  label: Text('$_newMessageCount条新消息',
                                      style: const TextStyle(fontSize: 11)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_replyDraft != null)
                        Container(
                            margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                            padding: const EdgeInsets.only(left: 10),
                            decoration: BoxDecoration(
                                color: BingoPalette.blush,
                                borderRadius: BorderRadius.circular(9)),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('回复 ${_senderName(_replyDraft!)}',
                                        style: const TextStyle(
                                            color: BingoPalette.primaryText,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                    Text(_preview(_replyDraft!.content),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: ChatScene.muted)),
                                  ])),
                              IconButton(
                                  tooltip: '取消引用',
                                  onPressed: () =>
                                      setState(() => _replyDraft = null),
                                  icon:
                                      const Icon(Icons.close_rounded, size: 17))
                            ])),
                      if (_mentionStart != null)
                        Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x100E5747), blurRadius: 16)
                                ]),
                            child: ListView(shrinkWrap: true, children: [
                              const Padding(
                                  padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
                                  child: Text('选择要 @ 的搭子',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: ChatScene.muted))),
                              if ('全部搭子'.contains(_mentionQuery) ||
                                  '全体搭子'.contains(_mentionQuery))
                                Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                        dense: true,
                                        leading: Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                                color: const Color(0xFFE4F5EC),
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                            child: const Center(
                                                child: Text('@',
                                                    style: TextStyle(
                                                        color: ChatScene.accent,
                                                        fontSize: 19,
                                                        fontWeight:
                                                            FontWeight.w700)))),
                                        title: const Text('全部搭子',
                                            style: TextStyle(fontSize: 13)),
                                        subtitle: Text(
                                            '${group?.activeMembers.length ?? 0} 位搭子都会回应',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: ChatScene.muted)),
                                        onTap: () => _selectMention(null))),
                              for (final person
                                  in group?.activeMembers ?? <GroupPerson>[])
                                if (person.name.contains(_mentionQuery) ||
                                    person.roleName.contains(_mentionQuery))
                                  Material(
                                      color: Colors.transparent,
                                      child: ListTile(
                                          dense: true,
                                          leading: AssistantAvatar(
                                              role: person.roleName, size: 32),
                                          title: Text(person.name,
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                          onTap: () => _selectMention(person))),
                            ])),
                      CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.keyZ,
                                control: true): _input.undo,
                            const SingleActivator(LogicalKeyboardKey.keyZ,
                                control: true, shift: true): _input.redo,
                            const SingleActivator(LogicalKeyboardKey.keyY,
                                control: true): _input.redo,
                          },
                          child: MessageInput(
                              enabled: !_chat.sending && group != null,
                              onSend: _send,
                              speechGateway: widget.speech,
                              onCall: _call,
                              onGallery: () => _image('pickImage'),
                              onCamera: () => _image('takePhoto'),
                              onLocation: _location,
                              textController: _input,
                              groupMenu: true,
                              hintText: '发消息到群聊…',
                              referenceStyle: true,
                              initialVoiceMode: false)),
                    ])))));
  }

  Widget _message(GroupChatMessage message, {GroupChatMessage? previous}) {
    if (message.type == 'system') {
      return Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
              child: Text(message.content,
                  style:
                      const TextStyle(fontSize: 11, color: ChatScene.muted))));
    }
    final user = message.type == 'user';
    final gap = previous == null
        ? null
        : message.createdAt.difference(previous.createdAt);
    final continuation = !user &&
        message.type == 'assistant' &&
        previous?.type == 'assistant' &&
        previous?.roleId == message.roleId &&
        previous?.name == message.name &&
        gap != null &&
        !gap.isNegative &&
        gap <= const Duration(minutes: 2);
    final sticker = ChatSticker.parse(message.content);
    final member = _chat.group?.members
        .where((person) => person.id == message.roleId)
        .firstOrNull;
    final colors = [
      ChatScene.muted,
      ChatScene.muted,
      ChatScene.muted,
      ChatScene.muted
    ];
    final index = switch (member?.roleName) {
      '女朋友' => 0,
      '男朋友' => 1,
      '同事' || '朋友' => 2,
      '老师' || '导师' => 3,
      _ => (_chat.group?.members
                  .indexWhere((person) => person.id == message.roleId) ??
              0)
          .clamp(0, colors.length - 1),
    };
    final avatar = ChatPortrait(
        size: 36,
        child: user
            ? UserAvatar(
                avatarData: widget.userAvatarData,
                username: _chat.group?.humanName ?? '',
                size: 36)
            : AssistantAvatar(role: member?.roleName, size: 36));
    final time = message.createdAt.toUtc().add(const Duration(hours: 8));
    final label =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
        onLongPress: () => _messageActions(message),
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
                color: _spotlight == message.id
                    ? const Color(0x3371CEB0)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14)),
            padding: EdgeInsets.only(top: continuation ? 1 : 6, bottom: 6),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment:
                    user ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (!user) ...[
                    continuation
                        ? const SizedBox.square(dimension: 36)
                        : avatar,
                    const SizedBox(width: 6)
                  ],
                  Flexible(
                      child: Column(
                          crossAxisAlignment: user
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                        if (!continuation || _replies.speakingId == message.id)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (user) ...[
                                      Text(label,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: ChatScene.muted)),
                                      const SizedBox(width: 8)
                                    ],
                                    Flexible(
                                        child: Text(
                                            user ? '我' : _senderName(message),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: user
                                                    ? ChatScene.accent
                                                    : colors[index < 0
                                                        ? 0
                                                        : index %
                                                            colors.length]))),
                                    if (!user) ...[
                                      const SizedBox(width: 8),
                                      Text(label,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: ChatScene.muted)),
                                      if (_replies.speakingId ==
                                          message.id) ...[
                                        const SizedBox(width: 6),
                                        const SpeakingWave(
                                            key:
                                                ValueKey('group-speaking-wave'),
                                            color: BingoPalette.primary),
                                      ]
                                    ]
                                  ])),
                        if (sticker != null && message.replyToId == null)
                          StickerMessageView(sticker)
                        else
                          Container(
                              constraints: BoxConstraints(
                                  maxWidth: MediaQuery.sizeOf(context).width *
                                      (message.replyToId == null ? .72 : .78)),
                              child: _GroupMessageSurface(
                                  isUser: user,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (message.replyToId != null)
                                          _quoteCard(message),
                                        if (message.attachment != null)
                                          _attachment(message)
                                        else if (sticker != null)
                                          StickerMessageView(sticker)
                                        else
                                          Text.rich(_contentSpan(message),
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  height: 1.45,
                                                  color: ChatScene.ink)),
                                        if (message.status == 'failed')
                                          const Text('回复未完成',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: ChatScene.muted)),
                                        if (message.status == 'sending')
                                          const Text('发送中…',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: ChatScene.muted)),
                                        if (message.status == 'send_failed')
                                          TextButton(
                                              onPressed: () =>
                                                  _retry(message.id),
                                              child: const Text('发送未确认，点此重试')),
                                        if (message.status == 'interrupted')
                                          const Text('已中断',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: ChatScene.muted))
                                      ]))),
                      ])),
                  if (user) ...[const SizedBox(width: 6), avatar],
                ])));
  }
}

class _GroupMessageSurface extends StatelessWidget {
  const _GroupMessageSurface({required this.isUser, required this.child});
  final bool isUser;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (AppearanceScope.skin(context).id != 'mint') {
      return BubbleSurface(isUser: isUser, child: child);
    }
    return SageBubble(isUser: isUser, child: child);
  }
}
