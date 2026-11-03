import asyncio
import json

import pytest
from fastapi.testclient import TestClient
from sqlmodel import select

from bingo.agent.model_client import ModelTextDelta
from bingo.config import Settings
from bingo.db.models import Memory
from bingo.db.models.groups import ChatGroup, GroupMemory, GroupMessage, GroupRun
from bingo.main import create_app
from tests.api_support import api_payload

P = "/api/v1"


class GroupModel:
    def __init__(self):
        self.contexts = []
        self.silent = False
        self.block = False
        self.entered = asyncio.Event()
        self.release = asyncio.Event()

    async def complete(self, messages):
        if "调度器" in messages[0].content:
            candidates = json.loads(messages[-1].content)["candidates"]
            count = 0 if self.silent else 1 if "至多一位" in messages[0].content else 2
            return json.dumps({"speakers": [item["id"] for item in candidates[:count]]})
        return json.dumps(["群里的公开约定：周末一起散步"])

    async def stream(self, messages, tools=None):
        self.contexts.append(messages)
        if self.block and len(self.contexts) == 1:
            self.entered.set()
            await self.release.wait()
        yield ModelTextDelta(f"伙伴回复第{len(self.contexts)}条。")


@pytest.fixture
def group_app(tmp_path):
    app = create_app(
        Settings(
            app={"environment": "test"},
            social_agent_runtime={"mode": "legacy_dispatcher"},
            model={"provider": "echo"},
            database={"url": f"sqlite+aiosqlite:///{tmp_path / 'groups.db'}"},
        )
    )
    with TestClient(app) as client:
        users = []
        for number in ("19933330001", "19933330002"):
            result = api_payload(
                client.post(P + "/auth/register", json={"phone": number, "password": "password123"})
            )
            users.append(
                ({"Authorization": "Bearer " + result["access_token"]}, result["user"]["id"])
            )
        alice = users[0][0]
        # Six built-ins plus two custom roles exercise the eight-AI group limit.
        roles = api_payload(client.get(P + "/roles", headers=alice))[:6]
        for index in range(2):
            response = client.post(
                P + "/roles",
                headers=alice,
                json={
                    "name": f"自定义伙伴{index}",
                    "prompt": "自然聊天",
                    "personality": "幽默风趣",
                },
            )
            roles.append(api_payload(response))
        model = GroupModel()
        app.state.services.group_chat.model = model
        # Most tests verify routing, budgets and persistence without wall-clock waits.
        # The pacing suite explicitly restores the production 1.5 second interval.
        app.state.services.group_chat.message_interval_seconds = 0
        yield client, users, roles, model


def create(client, headers, roles):
    result = client.post(
        P + "/groups",
        headers=headers,
        json={"name": "快乐小窝", "role_ids": [role["id"] for role in roles]},
    )
    assert result.status_code == 201, result.text
    return api_payload(result)


def test_creation_defaults_enable_all_features_and_respect_explicit_values(group_app):
    client, ((alice, _), _), roles, _ = group_app
    group = create(client, alice, roles[:2])
    for field in ("allow_ai_to_ai", "mentions_enabled", "proactive_enabled"):
        assert group[field] is True
    result = client.post(
        P + "/groups",
        headers=alice,
        json={
            "name": "自主设置",
            "role_ids": [role["id"] for role in roles[:2]],
            "allow_ai_to_ai": False,
            "mentions_enabled": False,
            "proactive_enabled": False,
        },
    )
    assert result.status_code == 201, result.text
    for field in ("allow_ai_to_ai", "mentions_enabled", "proactive_enabled"):
        assert api_payload(result)[field] is False


def wait(client):
    async def finish():
        await asyncio.gather(*list(client.app.state.services.group_chat.tasks.values()))

    client.portal.call(finish)


def test_mentions_eight_budget_ten_sequential_context_and_replay(group_app):
    client, ((alice, alice_id), _), roles, model = group_app
    group = create(client, alice, roles)

    async def memories():
        async with client.app.state.database.session_factory() as session:
            for index, role in enumerate(roles[:2]):
                session.add(
                    Memory(
                        user_id=alice_id,
                        role_id=role["id"],
                        scope="user_role",
                        content=f"PRIVATE_{index}",
                    )
                )
            await session.commit()

    client.portal.call(memories)
    payload = {
        "content": "大家来聊聊周末吧",
        "mentions": [role["id"] for role in roles],
        "client_message_id": "client-id-test-0001",
    }
    run = api_payload(client.post(P + f"/groups/{group['id']}/chat", headers=alice, json=payload))
    wait(client)
    messages = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=alice))
    ai = [message for message in messages if message["sender_type"] == "assistant"]
    assert len(ai) == 10
    assert len({message["sender_role_id"] for message in ai[:8]}) == 8
    assert [m["seq"] for m in messages] == list(range(1, 12))
    assert "PRIVATE_0" in model.contexts[0][0].content
    assert "PRIVATE_1" not in model.contexts[0][0].content
    assert "伙伴回复第1条" in model.contexts[1][-1].content
    endpoint = P + f"/groups/{group['id']}/runs/{run['run_id']}/events"
    replay = api_payload(client.get(endpoint, headers=alice))
    assert replay["status"] == "completed"
    seqs = [event["event_seq"] for event in replay["events"]]
    assert seqs == list(range(1, len(seqs) + 1))
    cursor = seqs[len(seqs) // 2]
    tail = api_payload(client.get(endpoint, headers=alice, params={"after_event_seq": cursor}))
    assert all(event["event_seq"] > cursor for event in tail["events"])
    repeat = api_payload(
        client.post(P + f"/groups/{group['id']}/chat", headers=alice, json=payload)
    )
    assert repeat["run_id"] == run["run_id"]
    assert len(api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=alice))) == 11
    assert client.post(P + f"/groups/{group['id']}/read?seq=11", headers=alice).status_code == 204
    assert api_payload(client.get(P + f"/groups/{group['id']}", headers=alice))["unread_count"] == 0

    async def remembered():
        async with client.app.state.database.session_factory() as session:
            assert (
                len(
                    (
                        await session.exec(
                            select(GroupMemory).where(GroupMemory.group_id == group["id"])
                        )
                    ).all()
                )
                == 1
            )

    client.portal.call(remembered)


def test_new_message_supersedes_pending_generation_without_late_writes(group_app):
    client, ((alice, _), _), roles, model = group_app
    model.block = True
    group = create(client, alice, roles[:2])

    def send(key, text):
        return api_payload(
            client.post(
                P + f"/groups/{group['id']}/chat",
                headers=alice,
                json={"client_message_id": key, "content": text, "mentions": [roles[0]["id"]]},
            )
        )

    first = send("client-old-run", "旧消息")
    client.portal.call(model.entered.wait)
    second = send("client-new-run", "用户新插话")
    client.portal.call(model.release.set)
    wait(client)
    old = api_payload(
        client.get(P + f"/groups/{group['id']}/runs/{first['run_id']}/events", headers=alice)
    )
    assert old["status"] == "cancelled"
    assert old["events"][-1]["type"] == "run_cancelled"
    current = api_payload(
        client.get(P + f"/groups/{group['id']}/runs/{second['run_id']}/events", headers=alice)
    )
    assert current["status"] == "completed"
    messages = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=alice))
    assert all(
        m["status"] == "interrupted"
        for m in messages
        if m["run_id"] == first["run_id"] and m["sender_type"] == "assistant"
    )


def test_silence_permissions_members_and_group_memory_isolation(group_app):
    client, ((alice, _), (bob, _)), roles, model = group_app
    group = create(client, alice, roles[:2])
    model.silent = True
    run = api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=alice,
            json={"client_message_id": "silence-test-id", "content": "大家安静待一会儿"},
        )
    )
    wait(client)
    events = api_payload(
        client.get(P + f"/groups/{group['id']}/runs/{run['run_id']}/events", headers=alice)
    )
    assert events["status"] == "completed"
    assert len(api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=alice))) == 1
    for path in ("", "/messages", f"/runs/{run['run_id']}/events"):
        assert client.get(P + f"/groups/{group['id']}" + path, headers=bob).status_code == 404
    assert (
        client.post(
            P + "/groups",
            headers=bob,
            json={"name": "越权群聊", "role_ids": [roles[-1]["id"], roles[0]["id"]]},
        ).status_code
        == 404
    )
    assert (
        client.delete(
            P + f"/groups/{group['id']}/members/{roles[0]['id']}", headers=alice
        ).status_code
        == 200
    )
    assert (
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=alice,
            json={
                "client_message_id": "removed-person-id",
                "content": "你好",
                "mentions": [roles[0]["id"]],
            },
        ).status_code
        == 422
    )
    other = create(client, alice, roles[2:4])

    async def isolated():
        async with client.app.state.database.session_factory() as session:
            assert not (
                await session.exec(select(GroupMemory).where(GroupMemory.group_id == other["id"]))
            ).all()

    client.portal.call(isolated)
    assert client.delete(P + f"/groups/{group['id']}/messages", headers=alice).status_code == 204
    assert not api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=alice))
    assert client.delete(P + f"/groups/{group['id']}", headers=alice).status_code == 204
    assert client.get(P + f"/groups/{group['id']}", headers=alice).status_code == 404


def test_startup_recovers_interrupted_run_and_preserves_history(group_app):
    client, ((alice, _), _), roles, _ = group_app
    group = create(client, alice, roles[:2])

    async def recover():
        async with client.app.state.database.session_factory() as session:
            row = await session.get(ChatGroup, group["id"])
            row.active_run_version = 1
            row.next_message_seq = 1
            run = GroupRun(
                group_id=row.id,
                client_message_id="crashed-client-id",
                request_json="{}",
                version=1,
                status="running",
            )
            session.add(run)
            session.add(
                GroupMessage(
                    group_id=row.id,
                    run_id=run.id,
                    seq=1,
                    sender_type="assistant",
                    sender_name="甜甜",
                    content="已收到的文字",
                    status="streaming",
                )
            )
            await session.commit()
            run_id = run.id
        await client.app.state.services.group_chat.start()
        return run_id

    run_id = client.portal.call(recover)
    result = api_payload(
        client.get(P + f"/groups/{group['id']}/runs/{run_id}/events", headers=alice)
    )
    assert result["status"] == "failed" and result["events"][-1]["type"] == "run_error"
    messages = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=alice))
    assert messages[0]["content"] == "已收到的文字" and messages[0]["status"] == "interrupted"


def test_ndjson_stream_uses_durable_ordered_events(group_app):
    client, ((alice, _), _), roles, model = group_app
    group = create(client, alice, roles[:2])
    model.silent = True
    response = client.post(
        P + f"/groups/{group['id']}/chat/stream",
        headers=alice,
        json={"content": "安静陪一会儿", "client_message_id": "ndjson-stream-test"},
    )
    assert response.status_code == 200
    assert "application/x-ndjson" in response.headers["content-type"]
    rows = [json.loads(line) for line in response.text.splitlines()]
    assert rows[0]["type"] == "run_start" and rows[-1]["type"] == "run_done"
    assert [row["event_seq"] for row in rows] == list(range(1, len(rows) + 1))


def test_community_trial_endpoint_is_removed(group_app):
    client, ((alice, _), _), _, _ = group_app
    response = client.post(
        P + "/community/characters/not-public/preview",
        headers=alice,
        json={"messages": [{"role": "user", "content": "hello"}]},
    )
    assert response.status_code == 404
