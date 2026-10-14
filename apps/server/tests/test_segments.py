import json
from pathlib import Path

import pytest

from bingo.prompts.system import SYSTEM_PROMPT
from bingo.utils.segments import split_complete_segments

CASES = json.loads(
    (
        Path(__file__).resolve().parents[2] / "mobile/test/fixtures/assistant_segments.json"
    ).read_text(encoding="utf8")
)


@pytest.mark.parametrize("case", CASES)
@pytest.mark.parametrize("chunk_size", [1, 2, 7, 1000])
def test_streaming_and_history_have_identical_bubbles(case: dict, chunk_size: int) -> None:
    pending = ""
    streamed: list[str] = []
    text = case["text"]
    for offset in range(0, len(text), chunk_size):
        pending += text[offset : offset + chunk_size]
        complete, pending = split_complete_segments(pending)
        streamed.extend(complete)
    complete, pending = split_complete_segments(pending, final=True)
    streamed.extend(complete)
    assert pending == ""
    assert streamed == case["expected"]
    assert split_complete_segments(text, final=True) == (case["expected"], "")


def test_scene_length_guidance_is_soft_and_respects_explicit_requests() -> None:
    assert "打招呼、早晚安、简单确认、日常闲聊和轻度关心通常 10～30 字" in SYSTEM_PROMPT
    assert "倾诉和安慰通常 30～70 字" in SYSTEM_PROMPT
    assert "天气、美食推荐、普通问答和一般建议通常 50～100 字" in SYSTEM_PROMPT
    assert "300～700" in SYSTEM_PROMPT
    assert "用户明确要求详细或简短时优先遵循" in SYSTEM_PROMPT
    assert "都是软目标，不是最低字数" in SYSTEM_PROMPT
