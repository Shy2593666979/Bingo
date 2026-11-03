import re

SEPARATOR_LINE = re.compile(r"^[ \t]*(?:[—―]{2,}|-{3,})[ \t]*(?:\r?\n|\Z)", re.MULTILINE)
DASH_OR_URL = re.compile(r"(?:https?://|www\.)[^\s<>“”]+|[—―]{2,}", re.IGNORECASE)
PENDING_SUFFIX = re.compile(r"(?:[-—―][-—― \t\r]*|[ \t\r]+)\Z")
PUNCTUATION = "，,。.!！?？；;：:、\n\r"
MENTION_BOUNDARY = r"(?=$|[\s，,。.!！？?：:、~～…])"


def strip_mentions_for_speech(text: str, names: list[str]) -> str:
    """Remove @name tokens so text-to-speech reads only the spoken content."""
    for name in sorted(set(names), key=len, reverse=True):
        if name:
            text = re.sub(r"\s*@" + re.escape(name) + MENTION_BOUNDARY, "", text)
    text = re.sub(r"\s*@(?:全部|全体)搭子", "", text)
    text = re.sub(r" +([，,。.!！?？；;：:、])", r"\1", text)
    text = re.sub(r"([，,。.!！?？；;：:、])(?=[，,。.!！?？；;：:、])", "", text)
    text = re.sub(r" {2,}", " ", text)
    return text.strip()


def clean_assistant_text(text: str) -> str:
    text = SEPARATOR_LINE.sub("", text)

    def replace(match: re.Match[str]) -> str:
        value = match.group()
        if value[0] not in "—―":
            return value
        previous = text[: match.start()].rstrip(" \t")[-1:]
        following = text[match.end() :].lstrip(" \t")[:1]
        if previous.isdigit() and following.isdigit():
            return value
        if not previous or not following or previous in PUNCTUATION or following in PUNCTUATION:
            return ""
        return "，"

    return DASH_OR_URL.sub(replace, text)


class AssistantTextCleaner:
    def __init__(self) -> None:
        self._pending = ""
        self._line_context = ""

    def feed(self, text: str, *, final: bool = False) -> str:
        ready = self._pending + text
        self._pending = ""
        if not final and (suffix := PENDING_SUFFIX.search(ready)):
            cut = suffix.start()
            line_start = ready.rfind("\n", 0, cut) + 1
            prefix = ready[line_start:cut]
            if line_start == 0:
                prefix = self._line_context + prefix
            if not prefix.strip():
                cut = line_start
            elif not any(character in "-—―" for character in suffix.group()):
                cut = len(ready)
            self._pending = ready[cut:]
            ready = ready[:cut]
        cleaned = clean_assistant_text(self._line_context + ready)
        output = cleaned[len(self._line_context) :]
        self._line_context = (self._line_context + output).rsplit("\n", 1)[-1]
        return output
