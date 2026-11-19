import 'package:flutter/material.dart';
import 'package:bingo/core/widgets/startup_brand_scene.dart';

/// Animated brand while restoring the session; no timed navigation.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(backgroundColor: Colors.white, body: const StartupBrandScene());
}
