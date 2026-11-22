import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';

class GroupCallPickerPage extends StatefulWidget {
  const GroupCallPickerPage({required this.group, super.key});
  final ChatGroup group;
  @override
  State<GroupCallPickerPage> createState() => _GroupCallPickerPageState();
}

class _GroupCallPickerPageState extends State<GroupCallPickerPage> {
  final selected = <String>{};
  @override
  Widget build(BuildContext context) {
    final members = widget.group.activeMembers;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F8),
      appBar: AppBar(title: const Text('选择通话搭子'), actions: [
        TextButton(
            onPressed: () => setState(() {
                  if (selected.length == members.length) {
                    selected.clear();
                  } else {
                    selected.addAll(members.map((m) => m.id));
                  }
                }),
            child: Text(selected.length == members.length ? '取消全选' : '全选')),
      ]),
      body: Column(children: [
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('选择一起语音聊天的搭子，你将自动加入通话。',
                style: TextStyle(color: Color(0xFF738297)))),
        Expanded(
            child: ListView(children: [
          for (final person in members)
            CheckboxListTile(
              value: selected.contains(person.id),
              onChanged: (value) => setState(() {
                value == true
                    ? selected.add(person.id)
                    : selected.remove(person.id);
              }),
              activeColor: BingoPalette.primary,
              secondary: AssistantAvatar(role: person.roleName, size: 48),
              title: Text(person.name),
              subtitle: Text(person.roleName),
            ),
        ])),
        SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(
                                context,
                                members
                                    .where((m) => selected.contains(m.id))
                                    .toList()),
                        child: Text(selected.isEmpty
                            ? '至少选择一位搭子'
                            : '发起通话（${selected.length}）'))))),
      ]),
    );
  }
}

class GroupCallPage extends StatefulWidget {
  const GroupCallPage(
      {required this.group,
      required this.members,
      required this.gateway,
      this.userAvatarData,
      super.key});
  final ChatGroup group;
  final List<GroupPerson> members;
  final GroupCallGateway gateway;
  final String? userAvatarData;
  @override
  State<GroupCallPage> createState() => _GroupCallPageState();
}

class _GroupCallPageState extends State<GroupCallPage>
    with WidgetsBindingObserver {
  static const device = MethodChannel('bingo/device_tools');
  static const microphone = EventChannel('bingo/audio_stream');
  WebSocket? socket;
  StreamSubscription<dynamic>? events, audio;
  Future<void> playback = Future.value();
  Timer? timer;
  String status = '正在连接…', caption = '', speakerName = '';
  String? speaker;
  int seconds = 0, generation = 0;
  String discussionPhase = 'idle';
  bool muted = false, loudspeaker = true, ending = false, allowPop = false;
  bool requestingAudio = false, failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(connect());
  }

  Future<void> connect() async {
    try {
      final value = await widget.gateway.connectGroupCall(
          widget.group.id, widget.members.map((m) => m.id).toList());
      if (!mounted || ending) {
        await value.close();
        return;
      }
      socket = value;
      events = value.listen(onEvent,
          onError: (Object error) => fail('连接已中断，请重新拨打'),
          onDone: () {
            if (!ending) fail('通话连接已结束');
          });
    } catch (_) {
      fail('无法接通，请检查网络或语音服务配置');
    }
  }

  void fail(String message) {
    if (!mounted || ending || failed) return;
    timer?.cancel();
    failed = true;
    if (socket?.readyState == WebSocket.open) {
      socket?.add(jsonEncode({'type': 'hangup'}));
    }
    unawaited(audio?.cancel());
    unawaited(device.invokeMethod<void>('stopCallAudio'));
    setState(() {
      status = message;
      speaker = null;
    });
  }

  void onEvent(dynamic raw) {
    if (ending || raw is! String) return;
    final event = jsonDecode(raw) as Map<String, dynamic>;
    final type = event['type'];
    final eventGeneration = event['generation'];
    if (eventGeneration is int && eventGeneration < generation) return;
    if (type == 'discussion_state') {
      setState(() {
        discussionPhase = event['phase'] as String? ?? 'idle';
        if (speaker == null) {
          status = discussionPhase == 'processing_user'
              ? '正在准备回应'
              : {'discussing', 'winding_down'}.contains(discussionPhase)
                  ? '大家正在聊天'
                  : '正在聆听';
        }
      });
      return;
    }
    if (type == 'command_error') {
      setState(() => status = event['message'] as String? ?? '操作未完成');
      return;
    }
    if (type == 'interrupted') {
      generation = event['generation'] as int;
      setState(() {
        speaker = null;
        status = '正在聆听';
      });
      unawaited(device.invokeMethod<void>('clearCallAudio'));
      return;
    }
    if (type == 'ready') {
      unawaited(startAudio());
      return;
    }
    if (type == 'error') {
      fail(event['message'] as String? ?? '语音服务不可用');
      return;
    }
    if (type == 'ended') {
      if (!failed) unawaited(finish(notify: false));
      return;
    }
    if (type == 'participant_error') {
      setState(() => status = event['message'] as String? ?? '搭子暂时无法回应');
      return;
    }
    if (type == 'user_transcript') {
      setState(() {
        caption = event['text'] as String;
        speakerName = widget.group.humanName;
      });
      return;
    }
    final epoch = event['generation'] as int? ?? generation;
    playback = playback.then((_) async {
      if (ending || epoch != generation || !mounted) return;
      switch (type) {
        case 'speaker':
          final id = event['role_id'] as String;
          setState(() {
            speaker = id;
            speakerName = widget.members.firstWhere((m) => m.id == id).name;
            caption = event['text'] as String;
            status = '$speakerName正在说话';
          });
        case 'audio':
          await device.invokeMethod<void>(
              'playCallAudio', base64Decode(event['data'] as String));
        case 'audio_end':
          final result = await device.invokeMethod<Object?>('finishCallAudio');
          final outcome = result is Map ? result['status'] : 'failed';
          if (!ending && epoch == generation) {
            socket?.add(jsonEncode({
              'type': 'played',
              'utterance_id': event['utterance_id'],
              'generation': epoch,
              'status': outcome
            }));
            if (mounted) {
              setState(() {
                speaker = null;
                status =
                    {'discussing', 'winding_down'}.contains(discussionPhase)
                        ? '大家正在聊天'
                        : '正在聆听';
              });
            }
          }
        case 'listening':
          setState(() {
            speaker = null;
            status = '正在聆听';
          });
      }
    }).catchError((Object _) {
      fail('通话音频异常，请重新拨打');
    });
  }

  Future<void> startAudio() async {
    requestingAudio = true;
    try {
      audio = microphone.receiveBroadcastStream().listen((dynamic data) {
        if (!ending && socket?.readyState == WebSocket.open) {
          if (data is Uint8List || data is List<int>) {
            final bytes = data as List<int>;
            socket?.add(muted ? Uint8List(bytes.length) : bytes);
          }
        }
      }, onError: (Object _) => fail('无法读取麦克风'));
      await device
          .invokeMethod<void>('startCallAudio', {'speaker': loudspeaker});
      if (!mounted || ending) return;
      socket?.add(
          jsonEncode({'type': 'client_audio_ready', 'playback_results': true}));
      setState(() => status = '正在聆听');
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => seconds++);
      });
    } catch (_) {
      fail('无法启用麦克风，请检查权限');
    } finally {
      requestingAudio = false;
    }
  }

  Future<void> finish({bool notify = true}) async {
    if (ending) return;
    ending = true;
    generation++;
    timer?.cancel();
    if (notify && socket?.readyState == WebSocket.open) {
      socket?.add(jsonEncode({'type': 'hangup'}));
    }
    await audio?.cancel();
    await device.invokeMethod<void>('stopCallAudio');
    await events?.cancel();
    await socket?.close();
    if (mounted) {
      setState(() => allowPop = true);
      Navigator.pop(context);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (requestingAudio) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(finish());
    }
  }

  @override
  void dispose() {
    ending = true;
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    unawaited(audio?.cancel());
    unawaited(events?.cancel());
    unawaited(socket?.close());
    unawaited(device.invokeMethod<void>('stopCallAudio'));
    super.dispose();
  }

  static const _callAccent = Color(0xFFCF6388);
  static const _callMuted = Color(0xFFA89AA1);

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(finish());
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
              child: Column(children: [
                Text(widget.group.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF302B2E))),
                const SizedBox(height: 12),
                Text(
                    '群聊语音 · ${widget.members.length + 1}人  ·  '
                    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 11, color: _callMuted)),
                const SizedBox(height: 22),
                Expanded(child: LayoutBuilder(builder: (context, constraints) {
                  final total = widget.members.length + 1;
                  final columns = total <= 4 ? 2 : 3;
                  final size = (constraints.maxWidth / columns - 30)
                      .clamp(44.0, total <= 4 ? 84.0 : 65.0);
                  final scale = MediaQuery.textScalerOf(context);
                  return Center(
                      child: SingleChildScrollView(
                    child: GridView.count(
                      key: const ValueKey('group-call-members'),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: columns,
                      mainAxisSpacing: total <= 4 ? 26 : 16,
                      crossAxisSpacing: 12,
                      mainAxisExtent: size +
                          30 +
                          scale.scale(14) * 1.4 +
                          scale.scale(10) * 1.3,
                      children: [
                        for (final member in widget.members)
                          _tile(
                              member.name,
                              AssistantAvatar(
                                  role: member.roleName,
                                  size: size,
                                  cornerRadius: size * .2),
                              speaker == member.id,
                              compact: total > 4),
                        _tile(
                            '${widget.group.humanName}（我）',
                            UserAvatar(
                                avatarData: widget.userAvatarData,
                                username: widget.group.humanName,
                                size: size),
                            false,
                            compact: total > 4,
                            self: true),
                      ],
                    ),
                  ));
                })),
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 12),
                  child: Text(status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              failed ? const Color(0xFFC85867) : _callMuted)),
                ),
                Container(
                  key: const ValueKey('group-call-captions'),
                  width: double.infinity,
                  height: 71 +
                      (MediaQuery.textScalerOf(context).scale(12) - 12) * 4,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFCF9FA),
                      borderRadius: BorderRadius.circular(10)),
                  child: SingleChildScrollView(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(caption.isEmpty ? '通话字幕' : '$speakerName · 实时字幕',
                          style: const TextStyle(
                              fontSize: 9, color: Color(0xFFB3A0A9))),
                      const SizedBox(height: 5),
                      Text(caption.isEmpty ? '说话时，字幕会显示在这里' : caption,
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.7,
                              color: Color(0xFF715B67))),
                    ],
                  )),
                ),
                const SizedBox(height: 27),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _action(
                          muted
                              ? Icons.mic_off_outlined
                              : Icons.mic_none_outlined,
                          muted ? '取消静音' : '静音',
                          () => setState(() => muted = !muted),
                          active: muted),
                      _action(Icons.call_end_rounded, '挂断',
                          () => unawaited(finish()),
                          destructive: true),
                      _action(
                          loudspeaker
                              ? Icons.volume_up_outlined
                              : Icons.hearing_outlined,
                          '免提', () async {
                        try {
                          await device.invokeMethod<void>(
                              'setCallSpeaker', !loudspeaker);
                          if (mounted) {
                            setState(() => loudspeaker = !loudspeaker);
                          }
                        } catch (_) {
                          fail('无法切换扬声器');
                        }
                      }, active: loudspeaker),
                    ]),
              ]),
            ),
          ),
        ),
      );

  Widget _tile(String name, Widget avatar, bool speaking,
          {bool compact = false, bool self = false}) =>
      Semantics(
          label: speaking ? '$name，正在说话' : name,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(compact ? 17 : 20),
                  border: Border.all(
                      color: speaking
                          ? const Color(0xFFDB94AF)
                          : Colors.transparent,
                      width: 1.5)),
              child: avatar,
            ),
            const SizedBox(height: 10),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: compact ? 11 : 14,
                    color: const Color(0xFF50474C))),
            const SizedBox(height: 6),
            SizedBox(
                height: MediaQuery.textScalerOf(context).scale(10) * 1.3,
                child: speaking
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            Icon(Icons.graphic_eq_rounded,
                                size: 13, color: _callAccent),
                            SizedBox(width: 3),
                            Text('说话中',
                                style:
                                    TextStyle(fontSize: 9, color: _callAccent)),
                          ])
                    : self && muted
                        ? const Text('已静音',
                            style: TextStyle(fontSize: 9, color: _callMuted))
                        : null),
          ]));

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {bool active = false, bool destructive = false}) =>
      SizedBox(
          width: 74,
          child: Column(children: [
            IconButton.filled(
              tooltip: label,
              onPressed: onTap,
              style: IconButton.styleFrom(
                  backgroundColor: destructive
                      ? const Color(0xFFED636B)
                      : active
                          ? const Color(0xFFF8EEF2)
                          : const Color(0xFFF5F3F4),
                  foregroundColor: destructive
                      ? Colors.white
                      : active
                          ? const Color(0xFFBD7693)
                          : const Color(0xFF71626B),
                  side: destructive
                      ? BorderSide.none
                      : BorderSide(
                          color: active
                              ? const Color(0xFFEEDBE4)
                              : const Color(0xFFEFEBED)),
                  fixedSize: const Size(62, 62)),
              icon: Icon(icon, size: 26),
            ),
            const SizedBox(height: 11),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF92868C))),
          ]));
}
