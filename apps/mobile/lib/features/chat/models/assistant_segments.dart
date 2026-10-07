List<String> splitAssistantBubbles(String content) {
  const sentenceMarks = '。！？!?…';
  const pairs = {
    '“': '”',
    '‘': '’',
    '（': '）',
    '(': ')',
    '[': ']',
    '【': '】',
    '《': '》',
    '"': '"',
  };
  final characters = content.runes.map(String.fromCharCode).toList();
  final segments = <String>[];
  final closing = <String>[];
  final structuredPrefix = RegExp(
    r'^(?:第[一二三四五六七八九十百0-9]+(?:天|步|阶段)(?=[：:\s]|上午|下午|晚上|早上|中午|$)|'
    r'(?:上午|下午|晚上|早上|中午|早餐|午餐|晚餐|预算(?:参考)?|交通|住宿|注意事项|'
    r'思路|说明|步骤[一二三四五六七八九十0-9]*|总结|建议)[：:]|'
    r'(?:Day|Step)\s*\d+|[1-9]\d*[、．])',
    caseSensitive: false,
  );
  final headingOnly = RegExp(
    r'^(?:第[一二三四五六七八九十百0-9]+(?:天|步|阶段)|(?:Day|Step)\s*\d+)[：:]?$',
    caseSensitive: false,
  );
  var start = 0;
  var index = 0;

  bool isSentenceMark(int position) {
    final character = characters[position];
    if (RegExp(r'(?:https?://|www\.)\S*$')
        .hasMatch(characters.take(position + 1).join())) {
      return '。！？…'.contains(character);
    }
    if (sentenceMarks.contains(character)) return true;
    if (character != '.') return false;
    if ((position > 0 && characters[position - 1] == '.') ||
        (position + 1 < characters.length && characters[position + 1] == '.')) {
      return true;
    }
    return position + 1 == characters.length ||
        characters[position + 1].trim().isEmpty;
  }

  void append(int end) {
    final segment = characters.sublist(start, end).join().trim();
    if (segment.isNotEmpty) segments.add(segment);
    start = end;
  }

  while (index < characters.length) {
    final character = characters[index];
    if (closing.isNotEmpty && character == closing.last) {
      closing.removeLast();
    } else if (pairs.containsKey(character)) {
      closing.add(pairs[character]!);
    } else if (character == '\n' && closing.isEmpty) {
      final segment = characters.sublist(start, index).join().trim();
      if (!headingOnly.hasMatch(segment)) {
        append(index);
        start = index + 1;
      }
    } else if (isSentenceMark(index)) {
      var end = index + 1;
      final followingClosing = List<String>.of(closing);
      while (end < characters.length) {
        final following = characters[end];
        if (followingClosing.isNotEmpty && following == followingClosing.last) {
          followingClosing.removeLast();
        } else if (!'$sentenceMarks.'.contains(following)) {
          break;
        }
        end++;
      }
      if (followingClosing.isEmpty) {
        final segment = characters.sublist(start, end).join().trim();
        if (segment.isNotEmpty && !structuredPrefix.hasMatch(segment)) {
          append(end);
        }
        closing
          ..clear()
          ..addAll(followingClosing);
        index = end;
        continue;
      }
    }
    index++;
  }
  append(characters.length);
  return segments;
}
