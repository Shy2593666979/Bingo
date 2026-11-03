import 'package:bingo/features/group_chat/presentation/mention_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MentionEditingController selected() {
    final c = MentionEditingController()..text = '@';
    c.insertMention(0, 1, 'role-1', '甜甜');
    return c;
  }

  test('editing any character removes the whole identity token', () {
    for (var position = 0; position < 3; position++) {
      final c = selected();
      c.value = TextEditingValue(
          text: c.text.replaceRange(position, position + 1, ''),
          selection: TextSelection.collapsed(offset: position));
      expect(c.text, ' ');
      expect(c.roleIds, isEmpty);
      c.dispose();
    }
  });

  test('partial selection replacement expands to whole token', () {
    final c = selected();
    c.value = const TextEditingValue(
        text: '@新甜 ', selection: TextSelection.collapsed(offset: 2));
    expect(c.text, '新 ');
    expect(c.tokens, isEmpty);
    c.dispose();
  });

  test('undo redo restores text and mention identities together', () {
    final c = selected();
    c.value = const TextEditingValue(
        text: '@甜 ', selection: TextSelection.collapsed(offset: 2));
    expect(c.roleIds, isEmpty);
    c.undo();
    expect(c.text, '@甜甜 ');
    expect(c.roleIds, ['role-1']);
    c.redo();
    expect(c.roleIds, isEmpty);
    c.dispose();
  });

  test('plain pasted display names do not create mention identities', () {
    final c = MentionEditingController()..text = '@甜甜 @全部搭子';
    expect(c.roleIds, isEmpty);
    expect(c.mentionAll, isFalse);
    c.dispose();
  });

  test('multiple identities survive adjacent typing and all deduplicates', () {
    final c = selected();
    c.value = TextEditingValue(
        text: '${c.text}@',
        selection: TextSelection.collapsed(offset: c.text.length + 1));
    c.insertMention(4, 5, 'all', '全部搭子', all: true);
    expect(c.roleIds, ['role-1']);
    expect(c.mentionAll, isTrue);
    c.value = TextEditingValue(
        text: '你好 ${c.text}',
        selection: const TextSelection.collapsed(offset: 3));
    expect(c.tokens.first.start, 3);
    expect(c.roleIds, ['role-1']);
    c.clear();
    expect(c.tokens, isEmpty);
    c.dispose();
  });
}
