import pytest

from bingo.utils.assistant_text import AssistantTextCleaner, clean_assistant_text

CASES = [
    ("抱抱你——今天辛苦了。", "抱抱你，今天辛苦了。"),
    ("抱抱你————今天辛苦了。", "抱抱你，今天辛苦了。"),
    ("你好。\n  ————  \n慢慢聊。", "你好。\n慢慢聊。"),
    ("你好。\r\n\t————\t\r\n慢慢聊。", "你好。\r\n慢慢聊。"),
    ("你好。\n---\n慢慢聊。", "你好。\n慢慢聊。"),
    ("你好——，今天辛苦了。", "你好，今天辛苦了。"),
    ("你好，——今天辛苦了。", "你好，今天辛苦了。"),
    ("——你好。", "你好。"),
    ("你好——", "你好"),
    (" ———— ", ""),
    ("---", ""),
    ("单个—符号保留。", "单个—符号保留。"),
    ("2026-10-09，-5℃，10:00-11:00，10:00–11:00。", "2026-10-09，-5℃，10:00-11:00，10:00–11:00。"),
    ("10:00——11:00，20——30分钟。", "10:00——11:00，20——30分钟。"),
    ("网址 https://example.test/a——b?q=-5", "网址 https://example.test/a——b?q=-5"),
    ("第一天上午：吃饭——逛公园。下午：休息。", "第一天上午：吃饭，逛公园。下午：休息。"),
]


@pytest.mark.parametrize(("raw", "expected"), CASES)
def test_cleanup_rules(raw, expected):
    assert clean_assistant_text(raw) == expected


@pytest.mark.parametrize(("raw", "expected"), CASES)
def test_stream_cleanup_is_independent_of_chunk_boundaries(raw, expected):
    for cut in range(len(raw) + 1):
        cleaner = AssistantTextCleaner()
        result = cleaner.feed(raw[:cut]) + cleaner.feed(raw[cut:]) + cleaner.feed("", final=True)
        assert result == expected, (raw, cut, result)
    cleaner = AssistantTextCleaner()
    result = "".join(cleaner.feed(character) for character in raw) + cleaner.feed("", final=True)
    assert result == expected


def test_normal_text_is_forwarded_immediately_and_only_ambiguous_tail_waits():
    cleaner = AssistantTextCleaner()
    assert cleaner.feed("抱抱你") == "抱抱你"
    assert cleaner.feed("—") == ""
    assert cleaner.feed("——") == ""
    assert cleaner.feed("今天辛苦了。") == "，今天辛苦了。"
    assert cleaner.feed("", final=True) == ""
    assert cleaner.feed("下一句。 ") == "下一句。 "
