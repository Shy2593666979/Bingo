import 'dart:ui' as ui;

import 'package:bingo/core/design/bingo_wordmark.dart';
import 'package:flutter/material.dart';

/// The same branded scene is used while restoring the session and loading home.
class StartupBrandScene extends StatefulWidget {
  const StartupBrandScene({this.onIntroComplete, super.key});

  final VoidCallback? onIntroComplete;

  @override
  State<StartupBrandScene> createState() => _StartupBrandSceneState();
}

class _StartupBrandSceneState extends State<StartupBrandScene>
    with TickerProviderStateMixin {
  late final _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onIntroComplete?.call();
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _pulse.stop();
    } else {
      if (_intro.value < 1 && !_intro.isAnimating) _intro.forward();
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  double _progress(double start, double end) => Curves.easeOutCubic.transform(
      ((_intro.value * 2600 - start) / (end - start)).clamp(0.0, 1.0));

  Widget _line(String text, Color color, double progress, String key) =>
      Opacity(
        key: ValueKey(key),
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, 5 * (1 - progress)),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
                sigmaX: 3 * (1 - progress), sigmaY: 3 * (1 - progress)),
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    height: 1.65,
                    letterSpacing: 1.2,
                    decoration: TextDecoration.none)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: Colors.white,
      child: AnimatedBuilder(
        animation: Listenable.merge([_intro, _pulse]),
        builder: (context, _) {
          final breath =
              reduced ? 0.0 : Curves.easeInOut.transform(_pulse.value);
          return Stack(fit: StackFit.expand, children: [
            // Keep the mascot still as the tagline appears below it.
            const Center(child: BingoWordmark(width: 174, height: 174)),
            Positioned.fill(
              child: LayoutBuilder(
                  builder: (context, constraints) => Stack(children: [
                        Positioned(
                          top: constraints.maxHeight / 2 + 87 + 27,
                          left: 0,
                          right: 0,
                          child: Semantics(
                            label: '每个人，都可以成为你的搭子。',
                            excludeSemantics: true,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _line(
                                      '每个人，',
                                      const Color(0xFF75676E),
                                      _progress(650, 2150),
                                      'startup-tagline-first'),
                                  _line(
                                      '都可以成为你的搭子。',
                                      const Color(0xFFD87694),
                                      _progress(1100, 2600),
                                      'startup-tagline-second'),
                                ]),
                          ),
                        ),
                      ])),
            ),
            Positioned(
              bottom: 105,
              left: 0,
              right: 0,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: _progress(1300, 2300),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                        3,
                        (index) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3.5),
                              child: Opacity(
                                opacity: reduced
                                    ? .65
                                    : .22 +
                                        .63 *
                                            (1 - (breath - index * .2).abs())
                                                .clamp(0.0, 1.0),
                                child: const SizedBox(
                                    width: 4,
                                    height: 4,
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: Color(0xFFEE5B88),
                                            shape: BoxShape.circle))),
                              ),
                            )),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
