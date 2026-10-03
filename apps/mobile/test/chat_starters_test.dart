import 'package:bingo/features/chat/presentation/chat_starters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('six built-in roles have three distinct conversational starters', () {
    const roles = ['女朋友', '男朋友', '同事', '老师', '家长', '小朋友'];
    final starters = <String>{};
    for (final role in roles) {
      final suggestions = chatStartersForRole(role);
      expect(suggestions, hasLength(3));
      expect(suggestions, isNot(defaultChatStarters));
      starters.addAll(suggestions);
    }
    expect(starters, hasLength(18));
  });

  test('custom and unspecified roles retain the default questions', () {
    expect(defaultChatStarters, [
      '帮我推荐一个好吃的',
      '最近休息不太好',
      '今天有点累，陪我聊聊吧',
    ]);
    expect(chatStartersForRole('custom-role-id'), defaultChatStarters);
    expect(chatStartersForRole(null), defaultChatStarters);
    expect(chatStartersForRole(''), defaultChatStarters);
  });

  test('updated questions retain the requested order', () {
    expect(chatStartersForRole('同事'), [
      '明天上班天气怎么样',
      '帮我理一理今天的工作安排',
      '这件工作有点棘手，帮我找个思路',
    ]);
    expect(chatStartersForRole('老师').first, '最近学习压力有点大');
    expect(chatStartersForRole('家长').last, '今天有什么新闻可以分享给我的');
  });
}
