"""Versioned sticker messages, persisted intact and converted at the model boundary."""

import json
import re

PREFIX = "[[bingo.sticker.v1]]"
SUFFIX = "[[/bingo.sticker]]"
PATTERN = re.compile(re.escape(PREFIX) + r"(\{[^\n]{1,3500}\})" + re.escape(SUFFIX))


def parse_sticker(content):
    if not content.startswith(PREFIX) or not content.endswith(SUFFIX):
        return None
    try:
        value = json.loads(content[len(PREFIX) : -len(SUFFIX)])
        if not isinstance(value, dict) or value.get("v") != 1:
            return None
        if not isinstance(value.get("id"), str) or len(value["id"]) > 80:
            return None
        for key, limit in [("label", 30), ("description", 300)]:
            if (
                not isinstance(value.get(key), str)
                or not value[key].strip()
                or len(value[key]) > limit
            ):
                return None
        return {key: value[key] for key in ["v", "id", "label", "description"]}
    except (ValueError, TypeError):
        return None


def encode_sticker(value):
    return (
        PREFIX
        + json.dumps(
            {"v": 1, **{key: value[key] for key in ["id", "label", "description"]}},
            ensure_ascii=False,
            separators=(",", ":"),
        )
        + SUFFIX
    )


def model_sticker_text(content):
    def replace(match):
        value = parse_sticker(match.group())
        if not value:
            return "[用户发送了表情]"
        return (
            f"用户发送了表情「{value['label']}」：{value['description']}。"
            "这是图片表达的含义，不直接断定用户此刻的心情。"
        )

    return PATTERN.sub(replace, content)


def preview_content(content):
    value = parse_sticker(content)
    return f"[表情] {value['label']}" if value else content
