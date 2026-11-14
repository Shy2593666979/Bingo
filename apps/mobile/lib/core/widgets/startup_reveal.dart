import 'package:flutter/material.dart';
import 'package:bingo/core/design/bingo_wordmark.dart';

/// Keeps the live, loading homepage mounted underneath the branded cover.
class StartupReveal extends StatefulWidget {
  const StartupReveal({required this.builder, super.key});
  final Widget Function(VoidCallback onReady) builder;
  @override
  State<StartupReveal> createState() => _StartupRevealState();
}

class _StartupRevealState extends State<StartupReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 850))
    ..repeat(reverse: true);
  bool _ready = false, _removed = false;
  void _onReady() {
    if (!mounted || _ready) return;
    _pulse.stop();
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
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
            duration: Duration(milliseconds: reduceMotion ? 0 : 280),
            curve: Curves.easeOutCubic,
            onEnd: () {
              if (_ready && mounted) setState(() => _removed = true);
            },
            child: ColoredBox(
              color: Colors.white,
              child: Center(
                  child: AnimatedBuilder(
                animation: _pulse,
                child: const BingoWordmark(width: 174, height: 68),
                builder: (context, child) => Transform.scale(
                    scale: reduceMotion
                        ? 1
                        : .98 + .02 * Curves.easeInOut.transform(_pulse.value),
                    child: Opacity(
                        opacity: reduceMotion ? 1 : .8 + .2 * _pulse.value,
                        child: child)),
              )),
            ),
          ),
        )),
    ]);
  }
}
