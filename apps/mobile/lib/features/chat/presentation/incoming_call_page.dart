import 'dart:async';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({
    required this.gateway,
    required this.invitation,
    super.key,
  });

  final CallInvitationGateway gateway;
  final IncomingCallInvitation invitation;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  static const _deviceChannel = MethodChannel('bingo/device_tools');

  Timer? _timer;
  int _secondsLeft = 30;
  bool _busy = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    unawaited(_startRinging());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    final seconds =
        widget.invitation.expiresAt.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) {
      if (!_finished) unawaited(_miss());
      return;
    }
    if (mounted) setState(() => _secondsLeft = seconds.clamp(1, 30));
  }

  Future<void> _startRinging() async {
    try {
      await _deviceChannel.invokeMethod<void>('startIncomingCallRinging');
    } on MissingPluginException {
      // Widget tests and non-Android targets do not provide the native channel.
    } on PlatformException {
      // The incoming-call UI remains usable if ringtone playback is unavailable.
    }
  }

  Future<void> _stopRinging() async {
    try {
      await _deviceChannel.invokeMethod<void>('stopIncomingCallRinging');
    } on MissingPluginException {
      // No native ringtone on this platform.
    } on PlatformException {
      // Nothing else is required when stopping an unavailable ringtone.
    }
  }

  Future<void> _accept() async {
    if (_busy || _finished) return;
    setState(() => _busy = true);
    try {
      await widget.gateway.acceptCallInvitation(widget.invitation.id);
      _finished = true;
      await _stopRinging();
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showCenterToast(context, '接听失败：$error');
    }
  }

  Future<void> _reject() async {
    if (_busy || _finished) return;
    _finished = true;
    setState(() => _busy = true);
    await _stopRinging();
    try {
      await widget.gateway.rejectCallInvitation(widget.invitation.id);
    } on Exception {
      // The UI should still close if the invitation expired while rejecting.
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _miss() async {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    await _stopRinging();
    try {
      await widget.gateway.missCallInvitation(widget.invitation.id);
    } on Exception {
      // The server also expires stale invitations when they are read again.
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_stopRinging());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_reject());
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: BingoPalette.softGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 70, 28, 44),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  AssistantAvatar(
                    role: widget.invitation.callerRole,
                    size: 124,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.invitation.callerName,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: BingoPalette.ink,
                        ),
                  ),
                  if (widget.invitation.callerRole case final role?) ...[
                    const SizedBox(height: 6),
                    Text(
                      role,
                      style: const TextStyle(
                        color: Color(0xFF65716D),
                        fontSize: 15,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    '邀请你进行语音通话 · $_secondsLeft 秒',
                    style: const TextStyle(color: Color(0xFF7A8581)),
                  ),
                  const Spacer(flex: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _IncomingCallAction(
                        icon: Icons.call_end_rounded,
                        label: '拒绝',
                        color: const Color(0xFFE85D5D),
                        onPressed: _busy ? null : _reject,
                      ),
                      _IncomingCallAction(
                        icon: Icons.call_rounded,
                        label: _busy ? '连接中' : '接听',
                        color: const Color(0xFF35B779),
                        onPressed: _busy ? null : _accept,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingCallAction extends StatelessWidget {
  const _IncomingCallAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox.square(
          dimension: 72,
          child: Material(
            color: onPressed == null ? color.withValues(alpha: 0.55) : color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Icon(icon, color: Colors.white, size: 34),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: BingoPalette.ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
