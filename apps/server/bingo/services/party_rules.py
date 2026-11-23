"""Deterministic rules and player-specific projections. No model controls legality."""

import copy
import secrets
from collections import Counter
from uuid import uuid4

from bingo.utils.segments import split_complete_segments

SELF = "self"
ROLES = {"wolf": "狼人", "seer": "预言家", "witch": "女巫", "villager": "村民"}


def split_party_bubbles(text: str) -> list[str]:
    paragraphs = [p.strip() for p in text.splitlines() if p.strip()]
    if not paragraphs:
        return [text.strip()] if text.strip() else []
    bubbles: list[str] = []
    for para in paragraphs:
        if len(para) <= 55:
            bubbles.append(para)
            continue
        segments, _ = split_complete_segments(para, final=True)
        if not segments:
            bubbles.append(para)
            continue
        current = ""
        for seg in segments:
            if not current:
                current = seg
            elif len(current) + len(seg) <= 55 or len(current) < 18:
                current += seg
            else:
                bubbles.append(current)
                current = seg
        if current:
            bubbles.append(current)
    return bubbles or [text.strip()]


def message(state, text, speaker=None, *, recipients=None, client_message_id=None):
    item = {"id": str(uuid4()), "text": text, "speaker": speaker, "round": state["round"]}
    if recipients is not None:
        item["recipients"] = list(recipients)
    if client_message_id is not None:
        item["client_message_id"] = client_message_id
    state["messages"].append(item)
    return item


def new_game(mode, people, username, rounds=5, identity=None):
    ids = [p["id"] for p in people]
    if len(ids) != len(set(ids)) or SELF in ids:
        raise ValueError("同一位搭子不能重复加入")
    if mode == "truth" and not 2 <= len(people) <= 5:
        raise ValueError("请选择 2～5 位搭子")
    if mode == "wolf" and len(people) not in {4, 6}:
        raise ValueError("狼人杀支持你和 4 或 6 位搭子")
    if mode not in {"truth", "wolf"} or rounds not in {3, 5, 8}:
        raise ValueError("玩法参数不正确")
    state = {
        "mode": mode,
        "host_id": (
            next((p["id"] for p in people if "老师" in p.get("avatar_key", "")), people[0]["id"])
            if mode == "truth"
            else None
        ),
        "people": [*people, {"id": SELF, "name": username}],
        "round": 1,
        "rounds": rounds,
        "phase": "select",
        "actor": None,
        "messages": [],
        "knowledge": {},
        "roles": {},
        "alive": [*ids, SELF],
        "paused": False,
        "error": None,
        "winner": None,
        "commands": [],
        "recent_actors": [],
        "recent_speakers": [],
        "discussion_turns": 0,
        "queue": [],
        "votes": {},
        "tie": False,
        "vote_candidates": [],
        "potion": {"save": True, "poison": True},
        "night": {},
        "voice": False,
        "read_aloud": True,
        "waiting_user": False,
        "user_pending": False,
        "voice_epoch": 0,
        "playback": None,
        "playback_checkpoint": None,
        "voice_suspended": False,
    }
    if mode == "wolf":
        deck = (
            ["wolf", "seer"] + ["villager"] * 3
            if len(people) == 4
            else ["wolf", "wolf", "seer", "witch"] + ["villager"] * 3
        )
        if identity is not None and identity not in deck:
            raise ValueError("该人数的对局没有这个身份")
        if identity:
            deck.remove(identity)
        secrets.SystemRandom().shuffle(deck)
        players = ids if identity else [*ids, SELF]
        state["roles"] = dict(zip(players, deck, strict=True))
        if identity:
            state["roles"][SELF] = identity
        wolves = [p for p in state["alive"] if state["roles"][p] == "wolf"]
        state["wolf_leader"] = secrets.choice(wolves)
        begin_night(state)
    return state


def visible_messages(state, player):
    return [
        {
            **{k: v for k, v in item.items() if k != "recipients"},
            **({"private": True} if "recipients" in item else {}),
        }
        for item in state["messages"]
        if "recipients" not in item or player in item["recipients"]
    ]


def private_view(state, player):
    view = {
        "identity": state["roles"].get(player),
        "clues": copy.deepcopy(state["knowledge"].get(player, [])),
    }
    if view["identity"] == "wolf":
        view["teammates"] = [p for p, role in state["roles"].items() if role == "wolf"]
        view["leader"] = state["wolf_leader"]
    if view["identity"] == "witch":
        view["potions"] = state["potion"].copy()
        if state["phase"] == "night" and state["actor"] == player:
            view["victim"] = state["night"].get("kill")
    return view


def options(state, player):
    if state["phase"] == "finished" or state["paused"]:
        return {}
    phase = state["phase"]
    if phase == "choose" and state["actor"] == player:
        return {"truth": "真心话", "dare": "大冒险"}
    if phase == "vote" and player in state["queue"]:
        return {
            **{p: name(state, p) for p in state["vote_candidates"] if p != player},
            "skip": "弃票",
        }
    if phase != "night" or state["actor"] != player:
        return {}
    action = state["night_action"]
    if action == "wolf_chat":
        return {}
    alive = state["alive"]
    if action == "kill":
        return {p: name(state, p) for p in alive if state["roles"][p] != "wolf"}
    if action == "check":
        checked = {c["target"] for c in state["knowledge"].get(player, [])}
        return {p: name(state, p) for p in alive if p != player and p not in checked} or {
            "skip": "没有新的可查验对象"
        }
    choices = {"skip": "不用药"}
    victim = state["night"].get("kill")
    if state["potion"]["save"] and victim and (victim != player or state["round"] == 1):
        choices["save"] = "使用解药"
    if state["potion"]["poison"]:
        choices.update({f"poison:{p}": f"毒杀{name(state, p)}" for p in alive if p != player})
    return choices


def name(state, player):
    return next(p["name"] for p in state["people"] if p["id"] == player)


def can_speak(state, player):
    phase = state["phase"]
    if (
        phase == "night"
        and player in state["alive"]
        and state["roles"].get(player) == "wolf"
        and state["night_action"] in {"wolf_chat", "kill"}
    ):
        return True
    return (
        (phase in {"answer", "speech", "last_words"} and state["actor"] == player)
        or (phase == "discuss" and player in state["alive"])
        or (phase == "night" and state["actor"] == player and state["night_action"] == "wolf_chat")
    )


def public_view(state, revision=0):
    return {
        "mode": state["mode"],
        "host_id": state["host_id"],
        "phase": state["phase"],
        "round": state["round"],
        "rounds": state["rounds"],
        "revision": revision,
        "action_stage": action_stage(state),
        "action_hint": action_hint(state),
        "people": state["people"],
        "alive": state["alive"],
        "actor": state["actor"]
        if state["phase"] != "night"
        else (SELF if state["actor"] == SELF else None),
        "messages": visible_messages(state, SELF),
        "private": private_view(state, SELF),
        "options": options(state, SELF),
        "can_speak": can_speak(state, SELF),
        "paused": state["paused"],
        "error": state["error"],
        "winner": state["winner"],
        "kind": state.get("kind"),
        "question": state.get("question"),
        "voice": state["voice"],
        "read_aloud": state.get("read_aloud", True),
        "waiting_user": state["waiting_user"],
        "voice_epoch": state["voice_epoch"],
        "playback": state["playback"],
        "can_advance": state["mode"] == "truth"
        or (state["phase"] == "discuss" and SELF in state["alive"]),
        "identities": state["roles"] if state["phase"] == "finished" else None,
    }


def action_stage(state):
    return f"{state['round']}:{state['phase']}:{state['actor'] == SELF}:{state['tie']}"


def action_hint(state):
    if state["actor"] == SELF:
        if state["phase"] == "night":
            if state["night_action"] == "potion":
                victim = state["night"].get("kill")
                return (
                    f"今晚被袭击的是{name(state, victim)}。" if victim else ""
                ) + "本晚最多使用一瓶药，也可以不用药"
            return {
                "wolf_chat": "狼队私聊，和队友商量今晚目标",
                "kill": "选择今晚袭击的目标",
                "check": "选择一位存活玩家查验",
                "potion": "本晚最多使用一瓶药，也可以不用药",
            }[state["night_action"]]
        if state["phase"] == "choose":
            return "轮到你了，真心话还是大冒险？"
        if state["phase"] == "last_words":
            return "你已出局，可以留下遗言，之后继续旁观"
        if state["phase"] in {"speech", "answer"}:
            return "轮到你发言，也可以直接说话"
    if state["phase"] == "vote" and SELF in state["queue"]:
        return "请独立投票，确认后不能修改"
    return None


def begin_night(state):
    state.update(
        phase="night",
        night={},
        votes={},
        tie=False,
        discussion_turns=0,
        waiting_user=False,
        user_pending=False,
    )
    wolves = [p for p in state["alive"] if state["roles"][p] == "wolf"]
    if state["wolf_leader"] not in wolves:
        state["wolf_leader"] = wolves[0]
    queue = [[p, "wolf_chat"] for p in wolves]
    queue += [[state["wolf_leader"], "kill"]]
    for role, action in [("seer", "check"), ("witch", "potion")]:
        queue += [[p, action] for p in state["alive"] if state["roles"][p] == role]
    state["queue"] = queue
    message(state, f"第 {state['round']} 夜，请按自己的身份行动。")
    next_night_actor(state)


def next_night_actor(state):
    if state["queue"]:
        state["actor"], state["night_action"] = state["queue"].pop(0)
        return
    night = state["night"]
    dead = set()
    if night.get("kill") and not night.get("save"):
        dead.add(night["kill"])
    if night.get("poison"):
        dead.add(night["poison"])
    state["alive"] = [p for p in state["alive"] if p not in dead]
    message(
        state,
        "天亮了。"
        + (
            "、".join(name(state, p) for p in sorted(dead)) + "出局。" if dead else "昨夜无人出局。"
        ),
    )
    if check_winner(state):
        return
    state["queue"] = list(sorted(dead)) if state["round"] == 1 else []
    if state["queue"]:
        state.update(phase="last_words", after_last="day", actor=state["queue"].pop(0))
    else:
        begin_day(state)


def night_choice(state, player, choice):
    if choice not in options(state, player):
        raise ValueError("无效的夜间操作")
    action = state["night_action"]
    if action == "kill":
        state["night"]["kill"] = choice
    elif action == "check" and choice != "skip":
        clue = {"day": state["round"], "target": choice, "wolf": state["roles"][choice] == "wolf"}
        state["knowledge"].setdefault(player, []).append(clue)
        message(
            state,
            f"查验结果：{name(state, choice)}是" + ("狼人。" if clue["wolf"] else "好人。"),
            recipients=[player],
        )
    elif action == "potion":
        if choice == "save":
            state["night"]["save"] = True
            state["potion"]["save"] = False
        elif choice.startswith("poison:"):
            state["night"]["poison"] = choice.partition(":")[2]
            state["potion"]["poison"] = False
    next_night_actor(state)


def begin_day(state):
    alive = state["alive"]
    offset = (state["round"] - 1) % len(alive)
    queue = alive[offset:] + alive[:offset]
    state.update(phase="speech", actor=queue[0], queue=queue[1:], discussion_turns=0)
    message(state, "白天开始，每位玩家先完整发言一次，再自由讨论。")


def begin_vote(state, candidates=None):
    state.update(
        phase="vote",
        actor=None,
        queue=state["alive"].copy(),
        votes={},
        vote_candidates=candidates or state["alive"].copy(),
        waiting_user=False,
    )
    message(state, "请独立投票，确认后不能修改；投票结束前不会公开其他人的选择。")


def cast_vote(state, player, choice):
    if choice not in options(state, player):
        raise ValueError("无效或重复投票")
    state["votes"][player] = choice
    state["queue"].remove(player)
    if state["queue"]:
        return
    counts = Counter(p for p in state["votes"].values() if p != "skip")
    message(
        state,
        "投票结果："
        + "；".join(
            f"{name(state, voter)}→{name(state, target) if target != 'skip' else '弃票'}"
            for voter, target in state["votes"].items()
        ),
    )
    top = [p for p, n in counts.items() if n == max(counts.values())] if counts else []
    if len(top) > 1 and not state["tie"]:
        state.update(tie=True, phase="speech", actor=top[0], queue=top[1:], tie_candidates=top)
        message(state, "出现平票，平票者各补充一次发言，然后重新投票。")
    elif len(top) == 1:
        state["alive"].remove(top[0])
        message(state, f"{name(state, top[0])}被投票出局。")
        if not check_winner(state):
            state.update(phase="last_words", actor=top[0], queue=[], after_last="night")
    else:
        message(state, "本次无人被放逐。")
        state["round"] += 1
        begin_night(state)


def check_winner(state):
    wolves = sum(state["roles"][p] == "wolf" for p in state["alive"])
    if wolves == 0 or wolves * 2 >= len(state["alive"]):
        state.update(phase="finished", actor=None, winner="good" if wolves == 0 else "wolf")
        message(state, "好人阵营获胜。" if wolves == 0 else "狼人阵营获胜。")
        return True
    return False


def spoken(state, player, text, *, client_message_id=None):
    if not can_speak(state, player):
        raise ValueError("当前阶段不能发言")
    private = (
        [p for p, r in state["roles"].items() if r == "wolf"]
        if (state["phase"] == "night")
        else None
    )
    chunks = (
        split_party_bubbles(text)
        if player != SELF and not state.get("voice")
        else [text]
    )
    for chunk in chunks:
        message(state, chunk, player, recipients=private, client_message_id=client_message_id)
    state["recent_speakers"] = [*state["recent_speakers"][-9:], player]
    state["waiting_user"] = False
    state["user_pending"] = player == SELF
    phase = state["phase"]
    if phase == "night":
        if state["night_action"] == "wolf_chat" and state["actor"] == player:
            next_night_actor(state)
    elif phase == "answer":
        state.update(phase="discuss", actor=None, discussion_turns=0)
    elif phase == "discuss":
        if player != SELF:
            state["discussion_turns"] += 1
    elif phase == "speech":
        if state["queue"]:
            state["actor"] = state["queue"].pop(0)
        elif state["tie"]:
            begin_vote(state, state["tie_candidates"])
        else:
            state.update(phase="discuss", actor=None)
    elif phase == "last_words":
        if state["queue"]:
            state["actor"] = state["queue"].pop(0)
        elif state["after_last"] == "day":
            begin_day(state)
        else:
            state["round"] += 1
            begin_night(state)


def next_truth(state):
    if state["round"] >= state["rounds"]:
        state.update(phase="finished", actor=None)
        message(state, "这次小聚结束了，聊天记录已保存。")
    else:
        state.update(
            round=state["round"] + 1,
            phase="select",
            actor=None,
            discussion_turns=0,
            question=None,
            kind=None,
            waiting_user=False,
            user_pending=False,
        )
