import asyncio
import json
import re

import pytest
from sqlmodel import select

from bingo.agent.model_client import ModelTextDelta
from bingo.agent.social_runtime import parse_intent
from bingo.db.models.groups import ChatGroup, GroupRun
from tests.api_support import api_payload
from tests.test_group_chat import P, create, group_app, wait  # noqa: F401


class IndependentModel:
    def __init__(self):
        self.decisions = []
        self.generations = []
        self.silent = False
        self.invalid = False
        self.fail_first = False
        self.quote = None
        self.user = None
        self.block = False
        self.entered = asyncio.Event()
        self.release = asyncio.Event()

    async def complete(self, messages):
        if '"action"' not in messages[-1].content:
            return "[]"
        self.decisions.append(messages)
        if self.invalid:
            return "not JSON"
        return json.dumps(
            {
                "action": "silent" if self.silent else "speak",
                "replyToMessageId": self.quote,
                "mentionTargets": [{"type": "user", "id": self.user}] if self.user else [],
            }
        )

    async def stream(self, messages, tools=None):
        self.generations.append(messages)
        if self.block:
            self.entered.set()
            await self.release.wait()
        if self.fail_first and len(self.generations) == 1:
            raise RuntimeError("provider unavailable")
        if "第一行" in messages[1].content:
            yield ModelTextDelta(
                json.dumps(
                    {
                        "replyToMessageId": self.quote,
                        "mentionTargets": [{"type": "user", "id": self.user}] if self.user else [],
                    }
                )
                + "\n"
            )
        yield ModelTextDelta("第一段，")
        yield ModelTextDelta("继续回应。")


@pytest.fixture
def v2(request):
    client, users, roles, _ = request.getfixturevalue("group_app")
    service = client.app.state.services.group_chat
    service.settings = service.settings.model_copy(update={"mode": "independent_agents"})
    model = IndependentModel()
    service.model = model
    return client, users, roles, model


def send(client, headers, group, **kwargs):
    payload = {"content": "聊聊周末吧", "clientMessageId": "v2-command-001", **kwargs}
    return client.post(P + f"/groups/{group['id']}/chat", headers=headers, json=payload)


def rows(client, headers, group):
    return api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))


def test_system_one_serial_turns_use_fresh_completed_history(v2):
    client, ((headers, _), _), roles, model = v2

    class Router:
        def __init__(self):
            self.states = []

        async def choose(self, state, candidates, **kwargs):
            self.states.append(state)
            count = len(self.states)
            if count == 3:
                return "finish"
            if count == 2:
                assert state["recent"][-1]["sender"] == "assistant"
                assert "第一段" in state["recent"][-1]["text"]
            return list(candidates)[count - 1]

        async def aclose(self):
            pass

    router = Router()
    client.app.state.services.group_chat.decision_model = router
    group = create(client, headers, roles)
    send(client, headers, group)
    wait(client)
    messages = rows(client, headers, group)
    ai = [m for m in messages if m["sender_type"] == "assistant"]
    assert len(ai) == 2
    assert ai[0]["sender_role_id"] != ai[1]["sender_role_id"]
    assert len(router.states) == 3


@pytest.mark.parametrize(
    "mode,allow_followup",
    [
        ("together", True),
        ("together", False),
        ("handoff", True),
    ],
)
def test_pending_participation_and_handoff_reach_the_other_member(v2, mode, allow_followup):
    client, ((headers, _), _), roles, model = v2
    first, second = [r["id"] for r in roles[:2]]

    class Router:
        classifications = 0
        states = []

        async def classify_group_user(self, state, candidates, **kwargs):
            self.classifications += 1
            assert set(candidates) == {first, second}
            return {
                "intent": mode if mode == "together" else "casual",
                "required_recipients": [first, second] if mode == "together" else [],
            }

        async def choose(self, state, candidates, **kwargs):
            self.states.append(state)
            if len(self.states) == 1:
                return first
            if len(self.states) == 2:
                assert set(candidates) == {second}
                assert state["pending_participants"] == [second]
                if mode == "handoff":
                    assert state["pending_handoffs"][0]["from"] == first
                return second
            assert not state["pending_participants"]
            return "finish"

        async def aclose(self):
            pass

    router = Router()
    client.app.state.services.group_chat.decision_model = router
    original = model.stream

    async def stream(messages, tools=None):
        if not model.generations and mode == "handoff":
            model.generations.append(messages)
            yield ModelTextDelta(
                json.dumps(
                    {
                        "replyToMessageId": None,
                        "mentionTargets": [{"type": "role", "id": second}],
                        "mentionAll": False,
                    }
                )
                + "\n这件事也想听听另一位的看法，请接着聊。"
            )
        else:
            async for chunk in original(messages, tools):
                yield chunk

    model.stream = stream
    group = create(client, headers, roles[:2])
    if not allow_followup:

        async def disable_followup():
            async with client.app.state.database.session_factory() as session:
                row = await session.get(ChatGroup, group["id"])
                row.allow_ai_to_ai = False
                await session.commit()

        client.portal.call(disable_followup)
    response = api_payload(send(client, headers, group, content="我想听你俩一起说话"))
    wait(client)
    ai = [m for m in rows(client, headers, group) if m["sender_type"] == "assistant"]
    assert [m["sender_role_id"] for m in ai] == [first, second]
    assert router.classifications == 1
    assert len(router.states) == (3 if allow_followup else 2)
    # Internal plan metadata must not break retry idempotency.
    retry = api_payload(send(client, headers, group, content="我想听你俩一起说话"))
    assert retry["run_id"] == response["run_id"]


def test_repeated_bad_speaker_choice_stops_without_forcing_other_members(v2):
    client, ((headers, _), _), roles, model = v2

    class Router:
        def __init__(self):
            self.states = []

        async def choose(self, state, candidates, **kwargs):
            self.states.append(state)
            assert state["latest_user"]["text"] == "哈喽"
            assert state["replies_since_user"] == len(self.states) - 1
            return next(iter(candidates))

        async def aclose(self):
            pass

    router = Router()
    client.app.state.services.group_chat.decision_model = router
    group = create(client, headers, roles[:2])
    send(client, headers, group, content="哈喽")
    wait(client)
    ai = [m for m in rows(client, headers, group) if m["sender_type"] == "assistant"]
    assert len(ai) == len(model.generations) == 2
    assert len({m["sender_role_id"] for m in ai}) == 1
    assert len(router.states) == 3
    assert router.states[-1]["consecutive_speaker_turns"] == 2
    run_id = ai[0]["run_id"]
    result = api_payload(
        client.get(P + f"/groups/{group['id']}/runs/{run_id}/events", headers=headers)
    )
    decisions = [e for e in result["events"] if e["type"] == "routing_decision"]
    assert len(decisions) == 3
    assert decisions[-1]["stop_reason"] == "consecutive_speaker_guard"


def test_decision_pause_produces_no_character_reply(v2):
    client, ((headers, _), _), roles, model = v2

    class Router:
        async def choose(self, state, candidates, **kwargs):
            assert state["user_pending"]
            return "pause"

        async def aclose(self):
            pass

    client.app.state.services.group_chat.decision_model = Router()
    group = create(client, headers, roles)
    send(client, headers, group)
    wait(client)
    assert not [m for m in rows(client, headers, group) if m["sender_type"] == "assistant"]
    assert not model.generations


def test_casual_exchange_cannot_give_same_role_third_turn_after_another_speaker(v2):
    client, ((headers, _), _), roles, model = v2
    first, second = [r["id"] for r in roles[:2]]

    class Router:
        choices = iter([first, second, first, first])

        async def classify_group_user(self, state, candidates, **kwargs):
            return {"intent": "directed", "required_recipients": []}

        async def choose(self, state, candidates, **kwargs):
            if state["replies_since_user"] == 3:
                assert state["consecutive_speaker_turns"] == 1
                assert state["speaker_reply_counts"][first] == 2
            return next(self.choices)

        async def aclose(self):
            pass

    client.app.state.services.group_chat.decision_model = Router()
    group = create(client, headers, roles[:2])
    run = api_payload(send(client, headers, group))
    wait(client)
    ai = [m for m in rows(client, headers, group) if m["sender_type"] == "assistant"]
    assert [m["sender_role_id"] for m in ai] == [first, second, first]
    events = api_payload(
        client.get(P + f"/groups/{group['id']}/runs/{run['run_id']}/events", headers=headers)
    )["events"]
    decisions = [e for e in events if e["type"] == "routing_decision"]
    assert decisions[-1]["stop_reason"] == "episode_speaker_guard"


def test_all_eight_strong_first_then_followups_budget_and_full_snapshot(v2):
    client, ((headers, _), _), roles, model = v2
    group = create(client, headers, roles)
    run = api_payload(send(client, headers, group, mentionAll=True, mentions=[roles[0]["id"]]))
    wait(client)
    messages = rows(client, headers, group)
    ai = [m for m in messages if m["sender_type"] == "assistant"]
    assert len(ai) == 10
    assert len({m["sender_role_id"] for m in ai[:8]}) == 8
    assert messages[0]["mention_all"] is True
    assert len(messages[0]["mention_targets"]) == 8
    assert all(m["status"] == "completed" for m in ai)
    events = api_payload(
        client.get(P + f"/groups/{group['id']}/runs/{run['run_id']}/events", headers=headers)
    )
    assert len(events["events"][0]["response_targets"]) == 8
    assert events["status"] == "completed"
    deltas = [e["message"]["content"] for e in events["events"] if e["type"] == "message_delta"]
    assert deltas[0] == "第一段，"
    assert len(model.decisions) <= 24
    assert len(model.generations) == 10
    own = [re.search(r"你的Role ID=([^；]+)", d[0].content).group(1) for d in model.generations[:8]]
    assert len(set(own)) == 8


def test_bad_decision_cannot_silence_strong_or_casual_human_message(v2):
    client, ((headers, _), _), roles, model = v2
    group = create(client, headers, roles[:2])
    model.invalid = True
    api_payload(send(client, headers, group, mentions=[roles[0]["id"]]))
    wait(client)
    assert len(model.generations) == 1
    api_payload(send(client, headers, group, clientMessageId="v2-command-002"))
    wait(client)
    assert len(model.generations) == 2


def test_quote_typed_human_mention_and_ownership(v2):
    client, ((headers, user_id), (other, other_id)), roles, model = v2
    group = create(client, headers, roles[:2])
    api_payload(send(client, headers, group, mentions=[roles[0]["id"]]))
    wait(client)
    original = rows(client, headers, group)[0]
    model.quote, model.user = original["id"], user_id
    api_payload(
        send(
            client,
            headers,
            group,
            clientMessageId="v2-command-002",
            mentionAll=True,
            replyToMessageId=original["id"],
        )
    )
    wait(client)
    messages = rows(client, headers, group)
    assert messages[-1]["reply_to"]["sender_name"] == original["sender_name"]
    assert messages[-1]["reply_to"]["created_at"] == original["created_at"]
    assert messages[-1]["mention_targets"] == [{"type": "user", "id": user_id}]
    info = api_payload(client.get(P + f"/groups/{group['id']}", headers=headers))
    assert info["unread_mentions"] > 0
    assert info["human"]["id"] == user_id
    assert messages[-1]["content"].startswith("@" + info["human"]["name"] + " ")
    assert (
        send(
            client,
            headers,
            group,
            clientMessageId="invalid-user-id",
            mentionTargets=[{"type": "user", "id": other_id}],
        ).status_code
        == 422
    )
    other_group = create(client, headers, roles[:2])
    assert send(client, headers, other_group, replyToMessageId=original["id"]).status_code == 422
    endpoint = P + f"/groups/{group['id']}/messages/{original['id']}/context"
    assert client.get(endpoint, headers=other).status_code == 404
    assert any(
        m["id"] == original["id"] for m in api_payload(client.get(endpoint, headers=headers))
    )


def test_provider_failure_does_not_drop_other_required_roles(v2):
    client, ((headers, _), _), roles, model = v2
    group = create(client, headers, roles[:3])
    model.fail_first = True
    api_payload(send(client, headers, group, mentionAll=True))
    wait(client)
    ai = [m for m in rows(client, headers, group) if m["sender_type"] == "assistant"]
    assert any(m["status"] == "failed" for m in ai)
    assert len({m["sender_role_id"] for m in ai if m["status"] == "completed"}) >= 2


def test_archive_invalidates_stream_preserves_settings_and_only_user_resumes(v2):
    client, ((headers, uid), _), roles, model = v2
    group = create(client, headers, roles[:2])
    model.block = True
    run = api_payload(send(client, headers, group, mentionAll=True))
    client.portal.call(model.entered.wait)
    url = P + f"/groups/{group['id']}"
    updated = api_payload(
        client.patch(url, headers=headers, json={"archived": True, "proactive_enabled": True})
    )
    assert updated["archived"] and updated["proactive_enabled"]
    client.portal.call(model.release.set)
    wait(client)
    assert api_payload(client.get(url, headers=headers))["archived"]
    assert all(m["status"] != "streaming" for m in rows(client, headers, group))
    status = api_payload(client.get(url + f"/runs/{run['run_id']}/events", headers=headers))[
        "status"
    ]
    assert status == "cancelled"
    count = len(model.generations)

    async def proactive():
        from bingo.db.models import User
        from bingo.schemas.group_chat import GroupSend

        service = client.app.state.services.group_chat
        async with client.app.state.database.session_factory() as session:
            user = await session.get(User, uid)
        return await service.begin(
            group["id"],
            user,
            GroupSend(client_message_id="proactive-archived-test", content="自动话题"),
            system=True,
        )

    assert client.portal.call(proactive)["status"] == "skipped"
    assert len(model.generations) == count
    model.block = False
    api_payload(
        send(client, headers, group, clientMessageId="resume-human-test", mentions=[roles[0]["id"]])
    )
    wait(client)
    assert not api_payload(client.get(url, headers=headers))["archived"]

    async def budget():
        async with client.app.state.database.session_factory() as session:
            runs = (await session.exec(select(GroupRun))).all()
            assert all(r.emitted_ai_messages <= 10 for r in runs)

    client.portal.call(budget)


def test_tolerant_decision_json_parser():
    assert parse_intent('```json\n{"action":"speak"}\n```').action == "speak"
    assert parse_intent('{"action":"unknown"}') is None
    assert parse_intent('{"action":"speak","desiredDelayMs":999999}') is None
    assert parse_intent("x" * 12001) is None


def test_upgrade_old_group_tables_keeps_records_and_is_idempotent():
    from sqlalchemy import create_engine

    from bingo.db.session import _upgrade_group_v2

    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        connection.exec_driver_sql("CREATE TABLE chat_group_messages (id TEXT PRIMARY KEY)")
        connection.exec_driver_sql("CREATE TABLE chat_group_runs (id TEXT PRIMARY KEY)")
        connection.exec_driver_sql("INSERT INTO chat_group_messages VALUES ('historical-message')")
        connection.exec_driver_sql("INSERT INTO chat_group_runs VALUES ('historical-run')")
        _upgrade_group_v2(connection)
        _upgrade_group_v2(connection)
        message = connection.exec_driver_sql("SELECT * FROM chat_group_messages").mappings().one()
        assert message["id"] == "historical-message"
        assert message["mention_targets_json"] == "[]"
        assert message["reply_to_message_id"] is None
        run = connection.exec_driver_sql("SELECT * FROM chat_group_runs").mappings().one()
        assert run["runtime_mode"] == "legacy_dispatcher"
        assert run["max_ai_messages"] == 10
    engine.dispose()


def test_quote_time_migration_backfills_original_time_without_changing_history():
    from sqlalchemy import create_engine

    from bingo.db.session import _upgrade_group_v2

    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        connection.exec_driver_sql(
            "CREATE TABLE chat_group_messages "
            "(id TEXT PRIMARY KEY, created_at DATETIME, reply_to_message_id TEXT)"
        )
        connection.exec_driver_sql("CREATE TABLE chat_group_runs (id TEXT PRIMARY KEY)")
        for values in [
            ("source", "2026-10-30 20:21:00", None),
            ("reply", "2026-10-30 20:22:00", "source"),
            ("missing", "2026-10-30 20:23:00", "removed"),
        ]:
            connection.exec_driver_sql("INSERT INTO chat_group_messages VALUES (?, ?, ?)", values)
        _upgrade_group_v2(connection)
        _upgrade_group_v2(connection)
        source, own = connection.exec_driver_sql(
            "SELECT reply_created_at, created_at FROM chat_group_messages WHERE id='reply'"
        ).one()
        assert source == "2026-10-30 20:21:00"
        assert own == "2026-10-30 20:22:00"
        assert (
            connection.exec_driver_sql(
                "SELECT reply_created_at FROM chat_group_messages WHERE id='missing'"
            ).scalar()
            is None
        )
    engine.dispose()
