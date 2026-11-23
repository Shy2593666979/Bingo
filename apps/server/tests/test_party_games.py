import asyncio
import json
from collections import Counter
from copy import deepcopy
from types import SimpleNamespace

import httpx
import pytest

from bingo.agent.decision_model_client import DecisionModelClient
from bingo.api.party_games import GameAction, GameCreate
from bingo.db.models import Role, User
from bingo.db.session import Database
from bingo.services import party_rules as r
from bingo.services.exceptions import ServiceError
from bingo.services.party_ai import context
from bingo.services.party_games import PartyGameService


def game(mode="wolf", n=6, identity=None):
    return r.new_game(
        mode, [{"id": str(i), "name": f"玩家{i}"} for i in range(n)], "用户", identity=identity
    )


@pytest.mark.parametrize(
    "n,expected",
    [
        (4, {"wolf": 1, "seer": 1, "villager": 3}),
        (6, {"wolf": 2, "seer": 1, "witch": 1, "villager": 3}),
    ],
)
def test_real_random_deck_and_user_identity(n, expected):
    for identity in expected:
        state = game(n=n, identity=identity)
        assert Counter(state["roles"].values()) == expected
        assert state["roles"]["self"] == identity


def test_private_context_and_client_projection_never_expose_deck_or_hidden_ballots():
    state = game(identity="villager")
    wolf = next(p for p, role in state["roles"].items() if role == "wolf")
    seer = next(p for p, role in state["roles"].items() if role == "seer")
    state["knowledge"][seer] = [{"target": wolf, "wolf": True, "day": 1}]
    r.message(state, "秘密狼队商议", wolf, recipients=[wolf])
    state["votes"] = {wolf: "self"}
    public = r.public_view(state)
    assert "秘密狼队商议" not in json.dumps(public, ensure_ascii=False)
    assert public["identities"] is None and public["private"]["clues"] == []
    for player in ["self", None, wolf]:
        data = context(state, player)
        assert "roles" not in data and "votes" not in data
        assert data["your_private_information"]["clues"] == []
    assert context(state, seer)["your_private_information"]["clues"][0]["wolf"]
    assert context(state, None)["your_private_information"]["identity"] is None


def test_night_legality_witch_consumption_and_seer_private_clues():
    state = game(identity="witch")
    state.update(actor="self", night_action="potion", night={"kill": "self"})
    assert r.public_view(state)["private"]["victim"] == "self"
    assert "用户" in r.public_view(state)["action_hint"]
    assert "save" in r.options(state, "self")
    state["round"] = 2
    assert "save" not in r.options(state, "self")
    with pytest.raises(ValueError):
        r.night_choice(state, "self", "save")
    target = next(p for p in state["alive"] if p != "self")
    state["queue"] = [["self", "potion"]]
    r.night_choice(state, "self", f"poison:{target}")
    assert state["potion"] == {"save": True, "poison": False}
    assert not any(p.startswith("poison:") for p in r.options(state, "self"))


def test_votes_sealed_duplicate_rejected_tie_second_tie_no_exile():
    state = game(n=4, identity="villager")
    r.begin_vote(state)
    r.cast_vote(state, "self", "0")
    assert r.public_view(state)["options"] == {}
    with pytest.raises(ValueError):
        r.cast_vote(state, "self", "1")
    for voter, choice in [("0", "1"), ("1", "0"), ("2", "1"), ("3", "skip")]:
        r.cast_vote(state, voter, choice)
    assert state["tie"] and state["phase"] == "speech"
    r.spoken(state, state["actor"], "我的理由")
    r.spoken(state, state["actor"], "我的理由")
    assert state["phase"] == "vote"
    before = state["alive"].copy()
    for voter, choice in [("self", "0"), ("0", "1"), ("1", "0"), ("2", "1"), ("3", "skip")]:
        r.cast_vote(state, voter, choice)
    assert state["alive"] == before and state["phase"] == "night" and state["round"] == 2


def test_dead_players_cannot_talk_and_parity_victory_is_rule_driven():
    state = game(identity="villager")
    state["alive"].remove("self")
    state.update(phase="discuss", actor=None)
    assert not r.can_speak(state, "self")
    assert not r.public_view(state)["can_advance"]
    with pytest.raises(ValueError):
        PartyGameService.apply(state, "advance", "")
    with pytest.raises(ValueError):
        r.spoken(state, "self", "不能给场上提示")
    wolves = [p for p, role in state["roles"].items() if role == "wolf"]
    good = [p for p, role in state["roles"].items() if role != "wolf"]
    state["alive"] = wolves + good[:2]
    assert r.check_winner(state) and state["winner"] == "wolf"
    assert r.public_view(state)["identities"] == state["roles"]


def test_wolf_private_interjection_cannot_skip_teammates_night_action():
    state = game(identity="wolf")
    other = next(p for p, role in state["roles"].items() if role == "wolf" and p != "self")
    state.update(actor=other, night_action="kill")
    queue = deepcopy(state["queue"])
    r.spoken(state, "self", "我想先讨论一下目标")
    assert state["actor"] == other and state["night_action"] == "kill" and state["queue"] == queue
    good = next(p for p, role in state["roles"].items() if role != "wolf")
    assert all(m["text"] != "我想先讨论一下目标" for m in r.visible_messages(state, good))


def test_truth_question_skip_and_interruption_preserve_current_task():
    state = game("truth", 2)
    state.update(phase="answer", actor="0", question="喜欢什么", kind="truth")
    PartyGameService.apply(state, "say", "我也想说说")
    assert state["actor"] == "0" and state["phase"] == "answer"
    assert context(state, "0")["history"][-1]["text"] == "我也想说说"
    state["actor"] = "self"
    PartyGameService.apply(state, "change_question", "")
    assert state["phase"] == "question" and state["question"] is None
    PartyGameService.apply(state, "advance", "")
    assert state["phase"] == "select" and state["round"] == 2


@pytest.mark.asyncio
async def test_systemone_generic_game_choice_has_no_group_finish_or_fallback():
    requests = []

    def handler(request):
        body = json.loads(request.content)
        requests.append(body)
        return httpx.Response(200, json={"answers": {"action": {"choice": "check"}}})

    settings = SimpleNamespace(
        endpoint="https://example.com/compatible-mode/v1/systemone",
        api_key="test",
        model="decision",
        timeout_seconds=5,
    )
    client = DecisionModelClient(settings, transport=httpx.MockTransport(handler))
    try:
        assert await client.decide({"phase": "night"}, {"check": "查验"}, "合法选择") == "check"
        assert requests[0]["questions"]["action"]["criteria"] == {"check": "查验"}
    finally:
        await client.aclose()


class Decision:
    async def decide(self, state, candidates, instructions):
        if "finish" in candidates:
            return "finish"
        if "self" in candidates:
            return "self"
        return next(iter(candidates))


class Model:
    async def complete(self, messages):
        return "这是根据当前对局生成的新内容。"


async def fixture(tmp_path):
    db = Database(f"sqlite+aiosqlite:///{tmp_path / 'games.db'}")
    await db.initialize()
    user = User(phone="game-user", password_hash="test", username="玩家")
    roles = [
        Role(
            code=f"party-{i}",
            name=f"测试{i}",
            nickname=f"搭子{i}",
            owner_id=user.id,
            avatar="boyfriend.png",
            prompt="独立角色",
        )
        for i in range(2)
    ]
    async with db.session_factory() as session:
        session.add(user)
        for role in roles:
            session.add(role)
        await session.commit()
    service = PartyGameService(db, Model(), Decision())
    return db, user, roles, service


async def wait_idle(service):
    for _ in range(100):
        tasks = list(service.tasks.values())
        if not tasks:
            return
        await asyncio.gather(*tasks, return_exceptions=True)
    raise AssertionError("game did not reach a user boundary")


@pytest.mark.asyncio
async def test_persistence_ownership_idempotency_and_restart_recovery(tmp_path):
    db, user, roles, service = await fixture(tmp_path)
    try:
        created = await service.create(
            user, GameCreate(mode="truth", role_ids=[p.id for p in roles])
        )
        await wait_idle(service)
        snapshot = await service.get(created["id"], user.id)
        assert snapshot["phase"] == "choose" and set(snapshot["options"]) == {"truth", "dare"}
        with pytest.raises(ServiceError):
            await service.get(created["id"], "other-user")
        command = GameAction(
            type="choice", value="truth", command_id="one-choice", revision=snapshot["revision"]
        )
        await service.action(created["id"], user.id, command)
        await wait_idle(service)
        before = await service.get(created["id"], user.id)
        assert before["phase"] == "answer"
        duplicate = await service.action(created["id"], user.id, command)
        assert duplicate["revision"] == before["revision"]
        await service.start()
        after = await service.get(created["id"], user.id)
        assert after["paused"] and after["messages"] == before["messages"]
        assert (await service.list(user.id))[0]["id"] == created["id"]
    finally:
        await service.close()
        await db.dispose()


@pytest.mark.asyncio
async def test_late_generation_cannot_overwrite_user_interruption(tmp_path):
    db, user, roles, service = await fixture(tmp_path)
    try:
        state = game("truth", 2)
        state["people"] = [{"id": p.id, "name": p.nickname} for p in roles] + [
            {"id": "self", "name": "玩家"}
        ]
        state.update(phase="answer", actor=roles[0].id, alive=[p["id"] for p in state["people"]])
        from bingo.db.models import PartyGame

        row = PartyGame(user_id=user.id, state_json=json.dumps(state))
        async with db.session_factory() as session:
            session.add(row)
            await session.commit()
        entered, release = asyncio.Event(), asyncio.Event()

        class Delayed(Model):
            async def complete(self, messages):
                entered.set()
                # Emulate a provider that returns despite cancellation.
                try:
                    await release.wait()
                except asyncio.CancelledError:
                    await release.wait()
                return "旧稿不能写入"

        service.ai.model = Delayed()
        service.kick(row.id, user.id)
        await entered.wait()
        await service.action(
            row.id, user.id, GameAction(type="pause", command_id="pause", revision=0)
        )
        release.set()
        await asyncio.sleep(0.05)
        result = await service.get(row.id, user.id)
        assert result["paused"]
        assert all(m["text"] != "旧稿不能写入" for m in result["messages"])
    finally:
        await service.close()
        await db.dispose()


@pytest.mark.asyncio
async def test_voice_turn_waits_for_exact_played_ack_and_old_ack_is_rejected(tmp_path):
    from bingo.db.models import PartyGame

    db, user, roles, service = await fixture(tmp_path)
    try:
        state = r.new_game("truth", [{"id": p.id, "name": p.nickname} for p in roles], "玩家")
        state.update(phase="answer", actor=roles[0].id, voice=True)
        row = PartyGame(user_id=user.id, state_json=json.dumps(state))
        async with db.session_factory() as session:
            session.add(row)
            await session.commit()
        service.kick(row.id, user.id)
        await wait_idle(service)
        snapshot = await service.get(row.id, user.id)
        assert snapshot["playback"] and len(snapshot["messages"]) == 1
        with pytest.raises(ServiceError):
            await service.action(
                row.id,
                user.id,
                GameAction(
                    type="played",
                    value=snapshot["playback"],
                    epoch=-1,
                    command_id="old-ack",
                    revision=snapshot["revision"],
                ),
            )
        paused = await service.action(
            row.id,
            user.id,
            GameAction(type="interrupt", command_id="barge-in", revision=snapshot["revision"]),
        )
        assert paused["playback"] is None
        assert paused["phase"] == "answer" and paused["actor"] == roles[0].id
        assert paused["messages"][-1]["playback_status"] == "interrupted"
        await wait_idle(service)
        assert len((await service.get(row.id, user.id))["messages"]) == 1
    finally:
        await service.close()
        await db.dispose()


@pytest.mark.asyncio
async def test_user_answer_gets_a_reply_and_followup_waits_instead_of_skipping():
    state = game("truth", 2)
    state.update(phase="discuss", user_pending=True)
    service = PartyGameService(None, Model(), Decision())
    seen = []

    class Followup:
        async def decide(self, context, options, instructions):
            seen.append(options)
            return "wait_user" if "wait_user" in options else "0"

    service.ai.decision = Followup()

    async def speak(*args):
        return "你最想先学哪一道菜？"

    service.say = speak
    await service.step(state, "unused")
    assert "finish" not in seen[0] and state["messages"][-1]["speaker"] == "0"
    await service.step(state, "unused")
    assert state["waiting_user"] and state["round"] == 1
    PartyGameService.apply(state, "say", "想学红烧肉")
    assert not state["waiting_user"] and state["user_pending"]
    assert state["discussion_turns"] == 1


@pytest.mark.asyncio
async def test_vote_accepts_same_stage_after_ai_votes_but_rejects_old_round(tmp_path):
    from bingo.db.models import PartyGame

    db, user, _, service = await fixture(tmp_path)
    try:
        state = game(n=4)
        r.begin_vote(state)
        stage = r.action_stage(state)
        r.cast_vote(state, "0", "1")
        row = PartyGame(user_id=user.id, revision=2, state_json=json.dumps(state))
        async with db.session_factory() as session:
            session.add(row)
            await session.commit()
        # Keep remaining AI ballots pending to inspect the user's submission alone.
        service.kick = lambda *args: None
        with pytest.raises(ServiceError):
            await service.action(
                row.id,
                user.id,
                GameAction(
                    type="choice", value="0", revision=0, stage="previous-round", command_id="stale"
                ),
            )
        await service.action(
            row.id,
            user.id,
            GameAction(type="choice", value="0", revision=0, stage=stage, command_id="valid-stage"),
        )
        after, _ = await service.load(row.id, user.id)
        assert after["votes"]["self"] == "0"
    finally:
        await service.close()
        await db.dispose()


@pytest.mark.asyncio
async def test_model_failure_pauses_without_inventing_reply_and_one_active_game(tmp_path):
    db, user, roles, service = await fixture(tmp_path)

    class Broken:
        async def decide(self, *args):
            raise ValueError("offline")

    service.ai.decision = Broken()
    try:
        payload = GameCreate(mode="truth", role_ids=[p.id for p in roles])
        created = await service.create(user, payload)
        await wait_idle(service)
        snapshot = await service.get(created["id"], user.id)
        assert snapshot["paused"] and snapshot["error"]
        assert snapshot["messages"] == []
        with pytest.raises(ServiceError):
            await service.create(user, payload)
    finally:
        await service.close()
        await db.dispose()


@pytest.mark.asyncio
@pytest.mark.parametrize("seats", [5, 7])
async def test_full_wolf_game_reaches_actual_winner_without_scripted_outcome(seats):
    service = PartyGameService(None, Model(), Decision())

    async def speak(state, user_id, player, instruction):
        assert "roles" not in context(state, player)
        return "这是我的判断和理由。"

    service.say = speak
    for _ in range(10):
        state = game(n=seats - 1)
        for _ in range(300):
            if state["phase"] == "finished":
                break
            phase, actor = state["phase"], state["actor"]
            if phase == "discuss":
                r.begin_vote(state)
            elif phase in {"speech", "last_words"} and actor == "self":
                r.spoken(state, "self", "我的公开发言")
            elif phase == "night" and actor == "self":
                if state["night_action"] == "wolf_chat":
                    r.spoken(state, "self", "狼队私聊")
                else:
                    r.night_choice(state, "self", next(iter(r.options(state, "self"))))
            elif phase == "vote" and "self" in state["queue"]:
                r.cast_vote(state, "self", next(iter(r.options(state, "self"))))
            else:
                assert await service.step(state, "unused")
        else:
            raise AssertionError("Game failed to terminate")
        assert state["winner"] in {"good", "wolf"}
        wolves = sum(state["roles"][p] == "wolf" for p in state["alive"])
        assert (wolves == 0) if state["winner"] == "good" else (wolves * 2 >= len(state["alive"]))
