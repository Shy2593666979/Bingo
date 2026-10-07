import 'dart:convert';
import 'dart:io';

import 'package:bingo/features/chat/models/assistant_segments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = jsonDecode(
    File('test/fixtures/assistant_segments.json').readAsStringSync(),
  ) as List;
  for (var index = 0; index < cases.length; index++) {
    final sample = cases[index] as Map<String, dynamic>;
    test('assistant bubble shared case $index', () {
      expect(
          splitAssistantBubbles(sample['text'] as String), sample['expected']);
    });
  }
}
