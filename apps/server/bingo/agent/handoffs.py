"""Resolve explicit human delegation; names alone are not recipient commands."""

import re
from collections import Counter


def ensure_human_mention(text, targets, human_id, human_name):
    """Keep a confirmed human mention visible in the persisted reply body."""
    if not human_name or not any(
        target.get("type") == "user" and target.get("id") == human_id
        for target in targets
    ):
        return text
    quoted = _quoted_positions(text)
    aliases = re.compile(
        r"@(?:我|" + re.escape(human_id) + r")"
        r"(?=$|[\s，,。.!！？?：:、~～…]|你|您|先|来|接|说|回|帮|给|请)"
    )
    text = aliases.sub(
        lambda match: match.group(0)
        if match.start() in quoted
        else "@" + human_name,
        text,
    )
    quoted = _quoted_positions(text)
    if any(match.start() not in quoted
           for match in re.finditer(re.escape("@" + human_name), text)):
        return text
    return "@" + human_name + " " + text


def requested_handoffs(text, people):
    if text.startswith("[[bingo.sticker"):
        return {}
    unique = Counter(people.values())
    result = {}
    for source, name in people.items():
        if unique[name] != 1:
            continue
        for target, other in people.items():
            if target == source or unique[other] != 1:
                continue
            pattern = (
                r"(?P<lead>让|叫|请|麻烦|拜托)?\s*(?P<source_at>@?)"
                + re.escape(name)
                + r"(?P<gap>[\s，,:：]*)(?P<assist>帮我|帮忙)?\s*(?P<go>去|来)?\s*"
                + r"(?P<verb>@|艾特|喊|叫|问问?|找|联系|转告|提醒|请|让)"
                + r"\s*(?:一下|一声)?\s*@?"
                + re.escape(other)
            )
            for match in re.finditer(pattern, text):
                if (
                    match["verb"] == "@"
                    and not any(match[k] for k in ["lead", "assist", "go"])
                    and (match["source_at"] or match["gap"])
                ):
                    # Adjacent selected @ tokens address both roles, not a delegation.
                    continue
                prefix = text[max(0, match.start() - 6) : match.start()].rstrip()
                if prefix.endswith(("不要", "不用", "别", "不许", "禁止", "无需", "不想")):
                    continue
                result.setdefault(source, [])
                if target not in result[source]:
                    result[source].append(target)
    return result


def initial_recipients(original, plan, all_targets=False):
    if not plan or all_targets:
        return original
    destinations = {target for targets in plan.values() for target in targets}
    sources = [id for id in plan if id not in destinations] or list(plan)
    return list(dict.fromkeys([*sources, *[id for id in original if id not in destinations]]))


def _quoted_positions(text):
    quoted = set()
    closers = {'“': '”', '「': '」', '『': '』', '‘': '’', '"': '"', '`': '`'}
    end = None
    for index, character in enumerate(text):
        if end:
            quoted.add(index)
            if character == end:
                end = None
        elif character in closers:
            quoted.add(index)
            end = closers[character]
    return quoted


def agent_broadcast_targets(text, people, sender_id):
    """@全部搭子 / @全体搭子 address other AI roles, never the speaker."""
    quoted = _quoted_positions(text)
    for match in re.finditer(
        r'@(?:全部|全体)搭子(?=$|[\s，,。.!！？?：:、~～…]|你|先|来|接|说|回|帮|给|请|们|大|每|各)',
        text,
    ):
        prefix = text[max(0, match.start() - 6):match.start()].rstrip()
        if match.start() in quoted or prefix.endswith(
            ('不要', '不用', '别', '不许', '禁止', '无需')
        ):
            continue
        return True, [{'type': kind, 'id': identifier} for kind, identifier, _ in people
                      if kind == 'role' and identifier != sender_id]
    return False, []


def normalize_agent_addresses(text, people, sender_id=None):
    """Bind explicit @ and narrow, direct invitations; ordinary names stay text.

    people contains validated (type, id, display_name) tuples from this group.
    Ambiguous names, self-mentions, quotations and negative requests are ignored.
    """
    unique = Counter(name for _, _, name in people)
    quoted = _quoted_positions(text)
    _, targets = agent_broadcast_targets(text, people, sender_id)
    insertions = set()
    boundary = r"(?=$|[\s，,。.!！？?：:、~～…]|你|先|来|接|说|回|帮|给|请)"
    action = (
        r"[\s，,:：]*(?:你\s*)?"
        r"(?:(?:(?:先|接着|再|来)\s*)?(?:接(?:一句|一下)?|说(?:一句话|一句|两句|几句|句话)|"
        r"说说|回答(?:一下)?|回应(?:一下)?|讲(?:一句|两句)|聊聊)|来(?:一句|接一下|说两句))"
        r"(?:吧|呀|呗|好吗|怎么样)?(?=$|[\s，,。.!！？?~～])"
    )
    for kind, identifier, name in people:
        if not name or unique[name] != 1 or (kind == 'role' and identifier == sender_id):
            continue
        explicit = list(re.finditer(r'@(?P<name>' + re.escape(name) + ')' + boundary, text))
        addressed = list(re.finditer(
            r'(?<![\w@])(?:请|让|麻烦|拜托)?\s*(?P<name>' + re.escape(name) + ')' + action,
            text,
        )) if kind == 'role' else []
        accepted = False
        for match in [*explicit, *addressed]:
            start = match.start('name')
            if start in quoted:
                continue
            prefix = text[max(0, match.start() - 6):match.start()].rstrip()
            if prefix.endswith(('不要', '不用', '别', '不许', '禁止', '无需')):
                continue
            accepted = True
            if match in addressed:
                insertions.add(start)
        if accepted:
            targets.append({'type': kind, 'id': identifier})
    for start in sorted(insertions, reverse=True):
        text = text[:start] + '@' + text[start:]
    return text, list({(t['type'], t['id']): t for t in targets}.values())
