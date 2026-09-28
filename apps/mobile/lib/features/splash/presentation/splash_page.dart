import 'package:flutter/material.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _textFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _textFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 0.9, curve: Curves.easeIn),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _playAnimation());
  }

  Future<void> _playAnimation() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    await _controller.forward();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FCFB),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Center(
              child: Semantics(
                label: 'Bingo',
                image: true,
                child: Image.asset(
                  'assets/images/bingo_logo.png',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            Center(
              child: Transform.translate(
                offset: const Offset(0, 140),
                child: FadeTransition(
                  opacity: _textFade,
                  child: Text(
                    '你的个人智能助理',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF475569),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
