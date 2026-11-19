import 'package:flutter/material.dart';
import 'package:bingo/core/widgets/startup_brand_scene.dart';

/// Keeps the live, loading homepage mounted underneath the branded cover.
class StartupReveal extends StatefulWidget {
  const StartupReveal({required this.builder, super.key});
  final Widget Function(VoidCallback onReady) builder;
  @override
  State<StartupReveal> createState() => _StartupRevealState();
}

class _StartupRevealState extends State<StartupReveal> {
  bool _ready = false, _removed = false;
  bool _dataReady = false, _introReady = false;
  void _onReady() {
    _dataReady = true;
    _revealWhenReady();
  }

  void _onIntroComplete() {
    _introReady = true;
    _revealWhenReady();
  }

  void _revealWhenReady() {
    if (!mounted || _ready || !_dataReady || !_introReady) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(fit: StackFit.expand, children: [
      ExcludeSemantics(
          excluding: !_ready,
          child: IgnorePointer(
              ignoring: !_ready, child: widget.builder(_onReady))),
      if (!_removed)
        Positioned.fill(
            child: IgnorePointer(
          ignoring: _ready,
          child: AnimatedOpacity(
            opacity: _ready ? 0 : 1,
            duration: Duration(milliseconds: reduceMotion ? 0 : 500),
            curve: Curves.easeOutCubic,
            onEnd: () {
              if (_ready && mounted) setState(() => _removed = true);
            },
            child: StartupBrandScene(onIntroComplete: _onIntroComplete),
          ),
        )),
    ]);
  }
}
