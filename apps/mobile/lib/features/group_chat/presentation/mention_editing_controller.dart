import 'package:flutter/material.dart';

/// Identity belongs to the selected token, never to text that merely looks like @name.
class MentionToken {
  const MentionToken(this.start, this.end, this.id, this.label,
      {this.all = false});
  final int start, end;
  final String id, label;
  final bool all;
  MentionToken shifted(int delta) =>
      MentionToken(start + delta, end + delta, id, label, all: all);
}

class _MentionSnapshot {
  _MentionSnapshot(this.value, this.tokens);
  final TextEditingValue value;
  final List<MentionToken> tokens;
}

class MentionEditingController extends TextEditingController {
  List<MentionToken> _tokens = [];
  final List<_MentionSnapshot> _undo = [], _redo = [];
  bool _restoring = false;
  List<MentionToken> get tokens => List.unmodifiable(_tokens);
  bool get mentionAll => _tokens.any((t) => t.all);
  List<String> get roleIds =>
      _tokens.where((t) => !t.all).map((t) => t.id).toSet().toList();
  bool containsCursor(int offset) =>
      _tokens.any((t) => offset > t.start && offset <= t.end);

  _MentionSnapshot get _snapshot => _MentionSnapshot(value, List.of(_tokens));
  void _remember() {
    _undo.add(_snapshot);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot);
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot);
    _restore(_redo.removeLast());
  }

  void _restore(_MentionSnapshot snapshot) {
    _restoring = true;
    _tokens = List.of(snapshot.tokens);
    super.value = snapshot.value;
    _restoring = false;
  }

  @override
  set value(TextEditingValue next) {
    if (_restoring || next.text == text) {
      super.value = next;
      return;
    }
    _remember();
    final old = text;
    var start = 0, suffix = 0;
    while (start < old.length &&
        start < next.text.length &&
        old.codeUnitAt(start) == next.text.codeUnitAt(start)) {
      start++;
    }
    while (suffix < old.length - start &&
        suffix < next.text.length - start &&
        old.codeUnitAt(old.length - 1 - suffix) ==
            next.text.codeUnitAt(next.text.length - 1 - suffix)) {
      suffix++;
    }
    var end = old.length - suffix;
    final inserted = next.text.substring(start, next.text.length - suffix);
    final touched = _tokens
        .where((t) =>
            (start < t.end && end > t.start) ||
            (start == end && start > t.start && start < t.end))
        .toList();
    for (final token in touched) {
      if (token.start < start) start = token.start;
      if (token.end > end) end = token.end;
    }
    final adjusted = old.replaceRange(start, end, inserted);
    final delta = inserted.length - (end - start);
    _tokens = [
      for (final token in _tokens)
        if (!touched.contains(token))
          token.start >= end ? token.shifted(delta) : token
    ];
    super.value = touched.isEmpty
        ? next
        : TextEditingValue(
            text: adjusted,
            selection:
                TextSelection.collapsed(offset: start + inserted.length));
  }

  void insertMention(int start, int end, String id, String label,
      {bool all = false}) {
    final replacement = '@$label ';
    value = TextEditingValue(
        text: text.replaceRange(start, end, replacement),
        selection: TextSelection.collapsed(offset: start + replacement.length));
    _tokens.add(MentionToken(start, start + replacement.length - 1, id, label,
        all: all));
    _tokens.sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final token in _tokens) {
      if (token.start < cursor || token.end > text.length) continue;
      spans.add(TextSpan(text: text.substring(cursor, token.start)));
      spans.add(TextSpan(
          text: text.substring(token.start, token.end),
          style: const TextStyle(
              color: Color(0xFF4F8164), fontWeight: FontWeight.w600)));
      cursor = token.end;
    }
    spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: style, children: spans);
  }
}
