import 'dart:async';

import 'package:bingo/app.dart';
import 'package:bingo/core/design/bingo_wordmark.dart';
import 'package:flutter/material.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  runApp(const BingoApp());

  // Decode the mascot before the first frame replaces the native splash.
  final ready = Completer<void>();
  final stream = BingoWordmark.asset.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener((image, _) {
    image.dispose();
    if (!ready.isCompleted) ready.complete();
  }, onError: (_, __) {
    if (!ready.isCompleted) ready.complete();
  });
  stream.addListener(listener);
  unawaited(ready.future
      .timeout(const Duration(seconds: 2), onTimeout: () {})
      .then((_) {
    stream.removeListener(listener);
    binding.allowFirstFrame();
  }));
}
