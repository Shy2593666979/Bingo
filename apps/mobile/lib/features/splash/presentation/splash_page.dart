import 'package:flutter/material.dart';
import 'package:bingo/core/design/bingo_wordmark.dart';

/// Static placeholder while restoring the session; no timed navigation.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
          child: Center(
              child: Semantics(
                  label: 'Bingo',
                  image: true,
                  child: const BingoWordmark(width: 174, height: 174)))));
}
