import 'dart:async';

import 'package:flutter/material.dart';

const centerToastDuration = Duration(seconds: 2);

void showCenterToast(
  BuildContext context,
  String message, {
  Duration duration = centerToastDuration,
}) {
  _CenterToastController.show(context, message, duration);
}

class _CenterToastController {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(BuildContext context, String message, Duration duration) {
    _timer?.cancel();
    _entry?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Semantics(
                liveRegion: true,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xD926312E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, () {
      if (identical(_entry, entry)) {
        entry.remove();
        _entry = null;
        _timer = null;
      }
    });
  }
}
