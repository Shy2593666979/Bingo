import 'package:bingo/features/chat/models/focus_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timer restores deadline instead of losing elapsed background time', () {
    final now = DateTime(2026, 10, 7, 12);
    final clock = FocusClock(totalSeconds: 1500, remainingSeconds: 1500)
      ..resume(now);
    final restored = FocusClock.fromJson(clock.toJson());
    expect(restored.remaining(now.add(const Duration(minutes: 10))), 900);
    expect(restored.remaining(now.add(const Duration(hours: 1))), 0);
  });
  test('pause and resume preserve actual remaining time', () {
    final now = DateTime(2026, 10, 7, 12);
    final clock = FocusClock(totalSeconds: 1500, remainingSeconds: 1500)
      ..resume(now);
    clock.pause(now.add(const Duration(minutes: 5)));
    expect(clock.remaining(now.add(const Duration(hours: 1))), 1200);
    clock.resume(now.add(const Duration(hours: 1)));
    expect(
        clock.remaining(now.add(const Duration(hours: 1, minutes: 10))), 600);
  });
}
