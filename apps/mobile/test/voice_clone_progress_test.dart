import 'package:bingo/features/auth/presentation/voice_clone_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clone progress is visible and shows the real processing stage',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: VoiceCloneProgress(message: '正在复刻声音，请稍等…'))));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('正在复刻声音，请稍等…'), findsOneWidget);
    expect(find.text('上传录音'), findsOneWidget);
    expect(find.text('云端复刻'), findsOneWidget);
    expect(find.text('验证音色'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
