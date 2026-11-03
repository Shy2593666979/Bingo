import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A playback indicator, not a microphone meter or a playback button.
class SpeakingWave extends StatefulWidget {
  const SpeakingWave({required this.color, super.key});
  final Color color;

  @override
  State<SpeakingWave> createState() => _SpeakingWaveState();
}

class _SpeakingWaveState extends State<SpeakingWave>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
    } else {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
      label: '正在朗读',
      child: ExcludeSemantics(
          child: SizedBox(
              width: 12,
              height: 12,
              child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, _) => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (var i = 0; i < 3; i++)
                              Container(
                                  key: ValueKey('speaking-wave-bar-$i'),
                                  width: 2,
                                  height: 3 +
                                      7 *
                                          (math.sin(_animation.value *
                                                      math.pi *
                                                      2 -
                                                  i * 1.3) +
                                              1) /
                                          2,
                                  decoration: BoxDecoration(
                                      color: widget.color,
                                      borderRadius: BorderRadius.circular(2)))
                          ])))));
}
