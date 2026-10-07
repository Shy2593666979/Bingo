import re

SENTENCE_MARKS = "。！？!?…"
PAIRS = {"“": "”", "‘": "’", "（": "）", "(": ")", "[": "]", "【": "】", "《": "》", '"': '"'}
STRUCTURED_PREFIX = re.compile(
    r"^(?:第[一二三四五六七八九十百0-9]+(?:天|步|阶段)(?=[：:\s]|上午|下午|晚上|早上|中午|$)|"
    r"(?:上午|下午|晚上|早上|中午|早餐|午餐|晚餐|预算(?:参考)?|交通|住宿|注意事项|"
    r"思路|说明|步骤[一二三四五六七八九十0-9]*|总结|建议)[：:]|"
    r"(?:Day|Step)\s*\d+|[1-9]\d*[、．])",
    re.IGNORECASE,
)
HEADING_ONLY = re.compile(
    r"^(?:第[一二三四五六七八九十百0-9]+(?:天|步|阶段)|(?:Day|Step)\s*\d+)[：:]?$",
    re.IGNORECASE,
)


def _is_sentence_mark(text: str, index: int) -> bool:
    character = text[index]
    if re.search(r"(?:https?://|www\.)\S*$", text[: index + 1]):
        return character in "。！？…"
    if character in SENTENCE_MARKS:
        return True
    if character != ".":
        return False
    if text[max(0, index - 1) : index] == "." or text[index + 1 : index + 2] == ".":
        return True
    return index + 1 == len(text) or text[index + 1].isspace()


def split_complete_segments(buffer: str, *, final: bool = False) -> tuple[list[str], str]:
    segments: list[str] = []
    closing: list[str] = []
    start = 0
    index = 0
    while index < len(buffer):
        character = buffer[index]
        if closing and character == closing[-1]:
            closing.pop()
        elif character in PAIRS:
            closing.append(PAIRS[character])
        elif character == "\n" and not closing:
            segment = buffer[start:index].strip()
            if not HEADING_ONLY.fullmatch(segment):
                if segment:
                    segments.append(segment)
                start = index + 1
        elif _is_sentence_mark(buffer, index):
            end = index + 1
            following_closing = closing.copy()
            while end < len(buffer):
                following = buffer[end]
                if following_closing and following == following_closing[-1]:
                    following_closing.pop()
                elif following not in SENTENCE_MARKS + ".":
                    break
                end += 1
            if not following_closing:
                if end == len(buffer) and not final:
                    break
                segment = buffer[start:end].strip()
                if segment and not STRUCTURED_PREFIX.match(segment):
                    segments.append(segment)
                    start = end
                closing = following_closing
                index = end
                continue
        index += 1
    remainder = buffer[start:]
    if final:
        if remainder.strip():
            segments.append(remainder.strip())
        remainder = ""
    return segments, remainder
