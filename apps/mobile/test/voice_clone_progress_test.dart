import 'package:bingo/features/auth/presentation/voice_clone_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clone progress is visible and shows the real processing stage',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: VoiceCloneProgress(message: '阿里云正在复刻声音…'))));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('阿里云正在复刻声音…'), findsOneWidget);
    expect(find.text('上传录音 → 复刻声音 → 验证音色'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
