import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/auth/data/introduction_audio_player.dart';
import 'package:bingo/shared/widgets/avatar_frame.dart';
import 'package:bingo/features/roles/role_traits.dart';

class CompanionSelectionPage extends StatefulWidget {
  const CompanionSelectionPage(
      {required this.gateway, required this.onComplete, super.key});
  final CompanionSelectionGateway gateway;
  final Future<void> Function(UserProfile) onComplete;
  @override
  State<CompanionSelectionPage> createState() => _CompanionSelectionPageState();
}

class _CompanionSelectionPageState extends State<CompanionSelectionPage>
    with WidgetsBindingObserver {
  static const green = Color(0xFF00A786);
  final _pager = PageController(viewportFraction: .80);
  final _audio = IntroductionAudioPlayer();
  final _selected = <String>{};
  List<RoleOption> _roles = [];
  Map<String, Map<String, dynamic>> _introductions = {};
  String? _error;
  bool _loading = true, _saving = false, _sound = true, _foreground = true;
  String? _audioError;
  int _index = 0, _voiceGeneration = 0;
  Timer? _voiceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.gateway.companionCandidates();
      final data = jsonDecode(
          await rootBundle.loadString('assets/onboarding/roles.json')) as List;
      if (!mounted) return;
      setState(() {
        _roles = items;
        _introductions = {
          for (final item in data)
            item['code'] as String: Map<String, dynamic>.from(item as Map)
        };
        _loading = false;
        if (items.isEmpty) _error = '暂时没有可选搭子，请稍后重试';
      });
      if (items.isNotEmpty) {
        _scheduleVoice();
        // 无限循环：跳到中间那份拷贝的首张，左右都能滑
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pager.hasClients) {
            _pager.jumpToPage(_roles.length);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '搭子加载失败，请检查网络后重试';
        });
      }
    }
  }

  String _code(RoleOption role) =>
      (role.avatarAsset ?? '').split('/').last.split('.').first;
  Map<String, dynamic> _intro(RoleOption role) =>
      _introductions[_code(role)] ?? {};
  String _line(RoleOption role) =>
      _intro(role)['intro'] as String? ?? role.openingLine;

  void _stopVoice() {
    _voiceGeneration++;
    _voiceTimer?.cancel();
    unawaited(_audio.stop());
  }

  void _scheduleVoice() {
    _stopVoice();
    if (!_sound || !_foreground || _saving || _roles.isEmpty) return;
    final generation = _voiceGeneration;
    _voiceTimer = Timer(const Duration(milliseconds: 280), () async {
      try {
        final data = await rootBundle
            .load('assets/onboarding/${_code(_roles[_index])}.m4a');
        if (!mounted || generation != _voiceGeneration) return;
        await _audio.play(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        if (mounted && generation == _voiceGeneration) {
          setState(() => _audioError = null);
        }
      } catch (_) {
        if (mounted && generation == _voiceGeneration) {
          setState(() => _audioError = '语音暂未播放，点击重听');
        }
      }
    });
  }

  void _nudge(int delta) {
    if (!_pager.hasClients || _roles.isEmpty) return;
    final page = _pager.page ?? 0;
    _pager.animateToPage(page.round() + delta,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _stopVoice();
  }

  Future<void> _submit() async {
    if (_selected.isEmpty || _saving) return;
    _stopVoice();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await widget.gateway.selectCompanions(_selected.toList());
      if (mounted) await widget.onComplete(profile);
    } catch (_) {
      if (mounted) setState(() => _error = '未能保存，请重试；已选搭子会保留');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopVoice();
    _pager.dispose();
    super.dispose();
  }

  Widget _portrait(RoleOption role, {BoxFit fit = BoxFit.cover}) => role
              .avatarData !=
          null
      ? Image.memory(base64Decode(role.avatarData!.split(',').last),
          fit: fit, alignment: Alignment.topCenter)
      : Image.asset(
          squareAvatarAsset(role.avatarAsset ?? 'assets/images/bingo_logo.png'),
          fit: fit,
          alignment: Alignment.topCenter);

  Widget _trait(String label, double s) => Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
      decoration: BoxDecoration(
          color: const Color(0xFFDDF6E5),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        TraitIcon(roleTraits[label] ?? 'chat',
            size: 15 * s, color: const Color(0xFF36B758)),
        SizedBox(width: 5 * s),
        Text(label,
            style: TextStyle(
                fontSize: 11 * s,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF28753D)))
      ]));

  Widget _card(RoleOption role, double s) {
    final selected = _selected.contains(role.id);
    final intro = _intro(role);
    return Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 8 * s),
        child: DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(27),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF53CE9E).withValues(alpha: .16),
                      blurRadius: 25,
                      offset: const Offset(0, 12))
                ]),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(27),
                child: LayoutBuilder(builder: (context, constraints) {
                  final height = constraints.maxHeight;
                  return DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(27),
                          border: Border.all(
                              color: selected
                                  ? const Color(0xFF6CD5A1)
                                  : Colors.white.withValues(alpha: .94),
                              width: 2)),
                      child: Stack(fit: StackFit.expand, children: [
                        const CustomPaint(painter: _CompanionBackdrop()),
                        Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: height * .54,
                            child: _portrait(role)),
                        Positioned(
                            right: 14 * s,
                            top: height * .47 - 43 * s,
                            child: IconButton.filledTonal(
                                tooltip: '重听${role.displayName}的介绍',
                                onPressed: _saving
                                    ? null
                                    : () {
                                        setState(() => _sound = true);
                                        _scheduleVoice();
                                      },
                                style: IconButton.styleFrom(
                                    fixedSize: Size.square(36 * s),
                                    minimumSize: Size.square(36 * s),
                                    padding: EdgeInsets.zero,
                                    backgroundColor:
                                        Colors.white.withValues(alpha: .96)),
                                icon: Icon(Icons.volume_up_rounded,
                                    size: 22 * s, color: green))),
                        Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: height * .54,
                            child: ClipPath(
                                clipper: const _CompanionWave(),
                                child: ColoredBox(
                                    color: Colors.white,
                                    child: Padding(
                                        padding: EdgeInsets.fromLTRB(
                                            19 * s, 23 * s, 19 * s, 18 * s),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              CustomPaint(
                                                  painter:
                                                      const _NameUnderline(),
                                                  child: Text(role.displayName,
                                                      style: TextStyle(
                                                          fontSize: 27 * s,
                                                          height: 1.15,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: const Color(
                                                              0xFF123C29)))),
                                              SizedBox(height: 3 * s),
                                              Text(
                                                  intro['relation']
                                                          as String? ??
                                                      role.typeLabel,
                                                  style: TextStyle(
                                                      fontSize: 13 * s,
                                                      height: 1.4,
                                                      color: const Color(
                                                          0xFF71867A))),
                                              SizedBox(height: 8 * s),
                                              Wrap(
                                                  spacing: 7 * s,
                                                  runSpacing: 4 * s,
                                                  children:
                                                      (intro['tags'] as List? ??
                                                              role.traits)
                                                          .take(2)
                                                          .map((tag) =>
                                                              _trait('$tag', s))
                                                          .toList()),
                                              SizedBox(height: 10 * s),
                                              Expanded(
                                                  child: Align(
                                                      alignment:
                                                          Alignment.topLeft,
                                                      child: Text(_line(role),
                                                          maxLines: 4,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                              fontSize: 13 * s,
                                                              height: 1.55,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: const Color(
                                                                  0xFF667D70))))),
                                              SizedBox(height: 10 * s),
                                              SizedBox(
                                                  width: double.infinity,
                                                  height: 43 * s,
                                                  child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(30),
                                                          gradient:
                                                              LinearGradient(
                                                                  begin: Alignment
                                                                      .topLeft,
                                                                  end: Alignment
                                                                      .bottomRight,
                                                                  colors:
                                                                      selected
                                                                          ? const [
                                                                              Color(0xFFE7F9ED),
                                                                              Color(0xFFDDF4E7)
                                                                            ]
                                                                          : const [
                                                                              Color(0xFF59D7AD),
                                                                              Color(0xFF06A873),
                                                                              Color(0xFF009E6C)
                                                                            ]),
                                                          boxShadow: selected
                                                              ? []
                                                              : [
                                                                  BoxShadow(
                                                                      color: const Color(0xFF00AE78).withValues(
                                                                          alpha:
                                                                              .15),
                                                                      blurRadius:
                                                                          14,
                                                                      offset:
                                                                          const Offset(
                                                                              0,
                                                                              6))
                                                                ]),
                                                      child: FilledButton(
                                                          onPressed: _saving
                                                              ? null
                                                              : () =>
                                                                  setState(() {
                                                                    selected
                                                                        ? _selected.remove(role
                                                                            .id)
                                                                        : _selected
                                                                            .add(role.id);
                                                                  }),
                                                          style: FilledButton.styleFrom(
                                                              padding: EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      6 * s),
                                                              backgroundColor: Colors
                                                                  .transparent,
                                                              disabledBackgroundColor:
                                                                  Colors
                                                                      .transparent,
                                                              shadowColor: Colors
                                                                  .transparent,
                                                              foregroundColor:
                                                                  selected
                                                                      ? green
                                                                      : Colors
                                                                          .white),
                                                          child:
                                                              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                            Icon(
                                                                selected
                                                                    ? Icons
                                                                        .check_circle_rounded
                                                                    : Icons
                                                                        .add_circle_rounded,
                                                                size: 19 * s),
                                                            SizedBox(
                                                                width: 8 * s),
                                                            Text(
                                                                selected
                                                                    ? '✓ 已添加，再点取消'
                                                                    : '添加为我的搭子',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        14 * s,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700))
                                                          ]))))
                                            ])))))
                      ]));
                }))));
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFFF0FCF6),
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFFF0FCF6),
          systemNavigationBarIconBrightness: Brightness.dark),
      child: Scaffold(
          backgroundColor: const Color(0xFFF0FCF6),
          body: DecoratedBox(
              decoration: const BoxDecoration(
                  gradient: RadialGradient(
                      center: Alignment(0, -.1),
                      radius: 1.15,
                      colors: [Color(0xFFDEF9EB), Color(0xFFF2FCF8)])),
              child: SafeArea(
                  child: LayoutBuilder(builder: (context, constraints) {
                final s = (constraints.maxHeight / 776).clamp(.78, 1.1);
                return Column(children: [
                  Padding(
                      padding: EdgeInsets.fromLTRB(12, 20 * s, 12, 16 * s),
                      child: Column(children: [
                        CustomPaint(
                            painter: const _TitleUnderline(),
                            child: Text('选几位喜欢的搭子',
                                style: TextStyle(
                                    fontSize: 26 * s,
                                    height: 1.4,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0D3624)))),
                        SizedBox(height: 8 * s),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                  width: 24 * s,
                                  height: 1,
                                  color: const Color(0xFFB5DDC8)),
                              SizedBox(width: 12 * s),
                              Text('左右滑动，听听 TA 的介绍',
                                  style: TextStyle(
                                      fontSize: 13 * s,
                                      color: const Color(0xFF71877C))),
                              SizedBox(width: 12 * s),
                              Container(
                                  width: 24 * s,
                                  height: 1,
                                  color: const Color(0xFFB5DDC8))
                            ])
                      ])),
                  Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _roles.isEmpty
                              ? Center(
                                  child: TextButton(
                                      onPressed: _load,
                                      child: Text(_error ?? '重新加载')))
                              : PageView.builder(
                                  controller: _pager,
                                  itemCount: _roles.length * 3,
                                  physics: const BouncingScrollPhysics(
                                      parent: PageScrollPhysics()),
                                  onPageChanged: (index) {
                                    final real = index % _roles.length;
                                    setState(() {
                                      _index = real;
                                      _audioError = null;
                                    });
                                    _scheduleVoice();
                                    if (index < _roles.length ||
                                        index >= _roles.length * 2) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (mounted && _pager.hasClients) {
                                          _pager
                                              .jumpToPage(_roles.length + real);
                                        }
                                      });
                                    }
                                  },
                                  itemBuilder: (_, index) => AnimatedBuilder(
                                      animation: _pager,
                                      builder: (context, child) {
                                        double delta = 1;
                                        if (_pager.hasClients &&
                                            _pager.position.haveDimensions) {
                                          delta = ((_pager.page ?? 0) - index)
                                              .abs()
                                              .clamp(0.0, 1.0);
                                        }
                                        return Transform.scale(
                                            scale: 1 - .09 * delta,
                                            child: Opacity(
                                                opacity: 1 - .5 * delta,
                                                child: child));
                                      },
                                      child: _card(
                                          _roles[index % _roles.length], s)))),
                  SizedBox(height: 15 * s),
                  if (_roles.isNotEmpty)
                    SizedBox(
                        height: 44 * s,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                  tooltip: '上一位',
                                  onPressed: () => _nudge(-1),
                                  icon: Icon(Icons.chevron_left_rounded,
                                      size: 25 * s,
                                      color: const Color(0xFF66A88E))),
                              Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 8 * s),
                                  child: Text(
                                      '${(_index + 1).toString().padLeft(2, '0')} / ${_roles.length.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                          fontSize: 15 * s,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF1D4533),
                                          letterSpacing: .5))),
                              IconButton(
                                  tooltip: '下一位',
                                  onPressed: () => _nudge(1),
                                  icon: Icon(Icons.chevron_right_rounded,
                                      size: 25 * s,
                                      color: const Color(0xFF66A88E)))
                            ])),
                  if (_audioError != null)
                    TextButton(
                        onPressed: _scheduleVoice,
                        child: Text(_audioError!,
                            style: const TextStyle(fontSize: 11))),
                  SizedBox(height: 16 * s),
                  Container(
                      margin: EdgeInsets.fromLTRB(6, 0, 6, 12 * s),
                      padding:
                          EdgeInsets.fromLTRB(18 * s, 15 * s, 18 * s, 17 * s),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .86),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white, width: 1.5)),
                      child: Column(children: [
                        Row(children: [
                          Semantics(
                              label: '已添加 ${_selected.length} 位',
                              excludeSemantics: true,
                              child: Text.rich(
                                  TextSpan(children: [
                                    const TextSpan(text: '已添加 '),
                                    TextSpan(
                                        text: '${_selected.length}',
                                        style: const TextStyle(
                                            color: Color(0xFF1FA648),
                                            fontWeight: FontWeight.w800)),
                                    const TextSpan(text: ' 位')
                                  ]),
                                  style: TextStyle(
                                      fontSize: 13 * s,
                                      color: const Color(0xFF6D8477)))),
                          SizedBox(width: 12 * s),
                          Expanded(
                              child: SizedBox(
                                  height: 29 * s,
                                  child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      children: _roles
                                          .where(
                                              (r) => _selected.contains(r.id))
                                          .map((role) => Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 6),
                                              child: Semantics(
                                                  label:
                                                      '移除${role.displayName}',
                                                  button: true,
                                                  child: InkWell(
                                                      onTap: _saving
                                                          ? null
                                                          : () => setState(() =>
                                                              _selected.remove(
                                                                  role.id)),
                                                      child: SizedBox.square(
                                                          dimension: 28 * s,
                                                          child:
                                                              Stack(children: [
                                                            Positioned.fill(
                                                                child:
                                                                    _portrait(
                                                                        role)),
                                                            const Positioned(
                                                                right: 0,
                                                                bottom: 0,
                                                                child: Icon(
                                                                    Icons
                                                                        .cancel,
                                                                    size: 11,
                                                                    color: Color(
                                                                        0xFF547C6A)))
                                                          ]))))))
                                          .toList())))
                        ]),
                        if (_error != null && _roles.isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(_error!,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.redAccent))),
                        SizedBox(height: 11 * s),
                        SizedBox(
                            width: double.infinity,
                            height: 44 * s,
                            child: FilledButton(
                                onPressed: _selected.isEmpty || _saving
                                    ? null
                                    : _submit,
                                style: FilledButton.styleFrom(
                                    backgroundColor: green,
                                    disabledBackgroundColor:
                                        const Color(0xFFE3EEEA),
                                    disabledForegroundColor:
                                        const Color(0xFF92AAA0),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(13))),
                                child: Text(
                                    _saving
                                        ? '正在保存…'
                                        : _selected.isEmpty
                                            ? '至少添加一位搭子'
                                            : '选好了，开始聊天',
                                    style: TextStyle(
                                        fontSize: 14 * s,
                                        fontWeight: FontWeight.w700))))
                      ]))
                ]);
              })))));
}

class _CompanionWave extends CustomClipper<Path> {
  const _CompanionWave();
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 25)
    ..cubicTo(size.width * .10, -9, size.width * .25, 0, size.width * .49, 12)
    ..cubicTo(size.width * .75, 26, size.width * .93, -10, size.width, 20)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();
  @override
  bool shouldReclip(_CompanionWave oldClipper) => false;
}

class _CompanionBackdrop extends CustomPainter {
  const _CompanionBackdrop();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE8FAF2), Color(0xFFD9F7E9)])
              .createShader(rect));
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height * .38)
          ..cubicTo(size.width * .24, size.height * .20, size.width * .58,
              size.height * .28, size.width, size.height * .09)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = const Color(0xFFBAEFCF).withValues(alpha: .45));
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height * .47)
          ..cubicTo(size.width * .25, size.height * .26, size.width * .63,
              size.height * .36, size.width, size.height * .22)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = const Color(0xFFE5FAEC).withValues(alpha: .75));
  }

  @override
  bool shouldRepaint(_CompanionBackdrop oldDelegate) => false;
}

class _NameUnderline extends CustomPainter {
  const _NameUnderline();
  @override
  void paint(Canvas canvas, Size size) => canvas.drawOval(
      Rect.fromLTWH(1, size.height * .70, size.width + 13, size.height * .25),
      Paint()..color = const Color(0xFFDDF7E5));
  @override
  bool shouldRepaint(_NameUnderline oldDelegate) => false;
}

class _TitleUnderline extends CustomPainter {
  const _TitleUnderline();
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
      Path()
        ..moveTo(size.width * .70, size.height - 1)
        ..quadraticBezierTo(
            size.width * .84, size.height - 5, size.width, size.height - 1),
      Paint()
        ..color = const Color(0xFF6DDBA0).withValues(alpha: .8)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);
  @override
  bool shouldRepaint(_TitleUnderline oldDelegate) => false;
}
