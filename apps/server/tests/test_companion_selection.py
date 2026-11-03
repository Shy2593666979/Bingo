import asyncio
import json

import pytest
from fastapi.testclient import TestClient

from bingo.config import Settings
from bingo.main import create_app
from tests.api_support import api_payload


class WelcomeModel:
    def __init__(self):
        self.prompts = []

    async def complete(self, messages):
        self.prompts.append(messages)
        data = json.loads(messages[-1].content)
        name = data["你"]["名字"]
        user = data["用户"]["昵称"]
        return json.dumps(
            {
                "private": f"{user}，我是{name}，很高兴认识你。今天想聊些什么？",
                "group": f"{name}来和{user}打招呼啦，大家慢慢聊。" if data["群内搭子"] else "",
            },
            ensure_ascii=False,
        )


def drain_welcomes(client):
    async def drain():
        from sqlmodel import select

        from bingo.db.models.welcome import WelcomeJob

        service = client.app.state.services.companion_welcome
        async with service.database.session_factory() as session:
            ids = (
                await session.exec(
                    select(WelcomeJob.id).where(WelcomeJob.status.in_(["queued", "retry"]))
                )
            ).all()
        await asyncio.gather(*(service.execute(identifier) for identifier in ids))

    client.portal.call(drain)


@pytest.fixture
def client(tmp_path):
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'selection.db'}"},
    )
    with TestClient(create_app(settings)) as connection:
        connection.app.state.services.companion_welcome.model = WelcomeModel()
        connection.app.state.services.companion_welcome.message_interval = 0
        yield connection


def register(client, *, modern=True, phone="19900111111"):
    response = client.post(
        "/api/v1/auth/register",
        json={"phone": phone, "password": "TestPassword2026", "companion_selection": modern},
    )
    assert response.status_code == 201, response.text
    auth = api_payload(response)
    client.headers["Authorization"] = f"Bearer {auth['access_token']}"
    return auth


def details(client):
    result = client.put(
        "/api/v1/me/user-profile",
        json={"username": "选择体验", "birthday": "2000-01-01", "gender": "女"},
    )
    assert result.status_code == 200, result.text


def test_modern_selection_only_adds_selected_and_survives_login(client):
    auth = register(client)
    assert not auth["user"]["companion_selection_complete"]
    assert api_payload(client.get("/api/v1/roles")) == []
    candidates = api_payload(client.get("/api/v1/onboarding/companions"))
    assert len(candidates) == 12
    ids = [role["id"] for role in candidates[:2]]
    assert client.post("/api/v1/onboarding/companions", json={"role_ids": ids}).status_code == 409
    details(client)
    response = client.post("/api/v1/onboarding/companions", json={"role_ids": ids})
    assert response.status_code == 200, response.text
    assert api_payload(client.get("/api/v1/onboarding/welcome"))["pending"]
    assert not client.app.state.services.companion_welcome.model.prompts
    drain_welcomes(client)
    assert not api_payload(client.get("/api/v1/onboarding/welcome"))["pending"]
    prompts = client.app.state.services.companion_welcome.model.prompts
    assert len(prompts) == len(ids)
    assert all(json.loads(p[-1].content)["用户"]["昵称"] == "选择体验" for p in prompts)
    assert api_payload(response)["companion_selection_complete"]
    assert {r["id"] for r in api_payload(client.get("/api/v1/roles"))} == set(ids)
    assert client.post("/api/v1/onboarding/companions", json={"role_ids": ids}).status_code == 200
    assert (
        client.post("/api/v1/onboarding/companions", json={"role_ids": [ids[0]]}).status_code == 409
    )
    blocked = candidates[2]["id"]
    assert client.post(f"/api/v1/roles/{blocked}/conversation").status_code == 404
    assert client.post(f"/api/v1/roles/{ids[0]}/conversation").status_code == 200
    assert (
        client.post(
            "/api/v1/groups", json={"name": "权限检查", "role_ids": [ids[0], blocked]}
        ).status_code
        == 404
    )
    created = client.post("/api/v1/roles", json={"name": "我的自定义搭子", "prompt": "认真倾听"})
    assert created.status_code == 201, created.text
    login = api_payload(
        client.post(
            "/api/v1/auth/login", json={"phone": "19900111111", "password": "TestPassword2026"}
        )
    )
    assert login["user"]["companion_selection_complete"]
    client.headers["Authorization"] = f"Bearer {login['access_token']}"
    assert len(api_payload(client.get("/api/v1/roles"))) == 3


def test_reject_empty_duplicate_unknown_and_foreign_roles(client):
    register(client)
    details(client)
    candidates = api_payload(client.get("/api/v1/onboarding/companions"))
    identifier = candidates[0]["id"]
    for ids in ([], [identifier, identifier], ["missing"], [identifier] * 13):
        assert (
            client.post("/api/v1/onboarding/companions", json={"role_ids": ids}).status_code == 422
        )
        assert not api_payload(client.get("/api/v1/me"))["companion_selection_complete"]
    assert api_payload(client.get("/api/v1/roles")) == []


def test_legacy_registration_keeps_catalogue(client):
    auth = register(client, modern=False)
    assert auth["user"]["companion_selection_complete"]
    assert len(api_payload(client.get("/api/v1/roles"))) == 12


def test_incomplete_registration_restores_selection_requirement(client):
    register(client)
    details(client)
    login = api_payload(
        client.post(
            "/api/v1/auth/login", json={"phone": "19900111111", "password": "TestPassword2026"}
        )
    )
    assert login["user"]["onboarding_complete"]
    assert not login["user"]["companion_selection_complete"]


@pytest.mark.parametrize("count", [1, 3, 8, 12])
def test_selection_creates_private_welcomes_and_capped_group_once(client, count):
    register(client)
    details(client)
    candidates = api_payload(client.get("/api/v1/onboarding/companions"))
    # Deliberately reverse catalogue order: the cap must follow selection order.
    selected = list(reversed(candidates))[:count]
    ids = [role["id"] for role in selected]
    response = client.post("/api/v1/onboarding/companions", json={"role_ids": ids})
    assert response.status_code == 200, response.text
    drain_welcomes(client)
    roles = api_payload(client.get("/api/v1/roles"))
    assert {role["id"] for role in roles} == set(ids)
    welcome_ids = set()
    for role in roles:
        assert role["message_count"] == 1
        assert role["unread_count"] == 1
        messages = api_payload(
            client.get(f"/api/v1/conversations/{role['conversation_id']}/messages")
        )
        assert len(messages) == 1
        message = messages[0]
        assert message["role"] == "assistant"
        assert role["nickname"] in message["content"]
        assert message["status"] == "completed"
        welcome_ids.add(message["id"])
    assert len(welcome_ids) == count

    groups = api_payload(client.get("/api/v1/groups"))
    if count == 1:
        assert groups == []
        assert (
            client.post("/api/v1/onboarding/companions", json={"role_ids": ids}).status_code == 200
        )
        assert len(client.app.state.services.companion_welcome.model.prompts) == 1
        return
    assert len(groups) == 1
    group = groups[0]
    assert 1 <= len(group["name"]) <= 20
    assert {m["id"] for m in group["members"]} == set(ids[:8])
    messages = api_payload(client.get(f"/api/v1/groups/{group['id']}/messages"))
    assert {m["sender_role_id"] for m in messages} == set(ids[:8])
    assert [m["seq"] for m in messages] == list(range(1, min(count, 8) + 1))
    assert all(m["status"] == "completed" and m["sender_name"] in m["content"] for m in messages)
    before = {m["id"] for m in messages}
    # Network retry must not send any new welcome or create another group.
    assert client.post("/api/v1/onboarding/companions", json={"role_ids": ids}).status_code == 200
    assert len(api_payload(client.get("/api/v1/groups"))) == 1
    assert {
        m["id"] for m in api_payload(client.get(f"/api/v1/groups/{group['id']}/messages"))
    } == before
    assert all(role["message_count"] == 1 for role in api_payload(client.get("/api/v1/roles")))


def test_model_failure_retries_without_any_canned_greeting(client):
    register(client)
    details(client)
    role = api_payload(client.get("/api/v1/onboarding/companions"))[0]
    client.post("/api/v1/onboarding/companions", json={"role_ids": [role["id"]]})
    service = client.app.state.services.companion_welcome

    class BrokenModel:
        async def complete(self, messages):
            raise RuntimeError("model temporarily unavailable")

    service.model = BrokenModel()
    for _ in range(3):
        drain_welcomes(client)
    assert api_payload(client.get("/api/v1/onboarding/welcome")) == {"pending": False, "failed": 1}
    item = api_payload(client.get("/api/v1/roles"))[0]
    messages = api_payload(client.get(f"/api/v1/conversations/{item['conversation_id']}/messages"))
    assert messages[0]["content"] == ""
    assert messages[0]["status"] == "interrupted"
    service.model = WelcomeModel()
    assert client.post("/api/v1/onboarding/welcome/retry").status_code == 200
    drain_welcomes(client)
    assert api_payload(client.get("/api/v1/onboarding/welcome")) == {"pending": False, "failed": 0}
    recovered = api_payload(client.get(f"/api/v1/conversations/{item['conversation_id']}/messages"))
    assert len(recovered) == 1 and recovered[0]["status"] == "completed"
    assert "选择体验" in recovered[0]["content"]


def test_failed_welcome_transaction_leaves_selection_retryable(client, monkeypatch):
    from bingo.services import companion_selection

    original = companion_selection.create_welcome_chats

    async def fail_after_inserts(*args):
        await original(*args)
        raise RuntimeError("simulated welcome failure")

    register(client)
    details(client)
    candidates = api_payload(client.get("/api/v1/onboarding/companions"))
    ids = [role["id"] for role in candidates[:2]]
    monkeypatch.setattr(companion_selection, "create_welcome_chats", fail_after_inserts)
    with pytest.raises(RuntimeError, match="simulated welcome failure"):
        client.post("/api/v1/onboarding/companions", json={"role_ids": ids})
    assert not api_payload(client.get("/api/v1/me"))["companion_selection_complete"]
    assert api_payload(client.get("/api/v1/roles")) == []
    assert api_payload(client.get("/api/v1/groups")) == []
    monkeypatch.setattr(companion_selection, "create_welcome_chats", original)
    assert client.post("/api/v1/onboarding/companions", json={"role_ids": ids}).status_code == 200
    assert len(api_payload(client.get("/api/v1/groups"))) == 1


def test_restart_recovers_saved_generation_without_another_model_call(client):
    from sqlmodel import select

    from bingo.db.models.welcome import WelcomeJob

    register(client)
    details(client)
    role = api_payload(client.get("/api/v1/onboarding/companions"))[0]
    client.post("/api/v1/onboarding/companions", json={"role_ids": [role["id"]]})
    service = client.app.state.services.companion_welcome

    async def simulate_restart():
        async with service.database.session_factory() as session:
            job = (await session.exec(select(WelcomeJob))).one()
            job.status = "running"
            job.result_json = json.dumps(
                {"private": "选择体验，见到你真开心。我们慢慢聊。", "group": ""}
            )
            await session.commit()
        await service.start()
        for _ in range(100):
            async with service.database.session_factory() as session:
                state = (await session.exec(select(WelcomeJob.status))).one()
            if state == "completed":
                break
            await asyncio.sleep(0.02)
        await service.close()
        return state

    assert client.portal.call(simulate_restart) == "completed"
    assert service.model.prompts == []
    item = api_payload(client.get("/api/v1/roles"))[0]
    messages = api_payload(client.get(f"/api/v1/conversations/{item['conversation_id']}/messages"))
    assert len(messages) == 1 and messages[0]["content"] == "选择体验，见到你真开心。我们慢慢聊。"


def test_waiting_welcome_does_not_block_user_or_publish_after_user_speaks(client):
    from sqlmodel import select

    from bingo.db.models.groups import ChatGroup, GroupMessage
    from bingo.db.models.welcome import WelcomeJob

    register(client)
    details(client)
    roles = api_payload(client.get("/api/v1/onboarding/companions"))[:2]
    client.post("/api/v1/onboarding/companions", json={"role_ids": [r["id"] for r in roles]})
    service = client.app.state.services.companion_welcome

    async def scenario():
        async with service.database.session_factory() as session:
            ids = (await session.exec(select(WelcomeJob.id).order_by(WelcomeJob.created_at))).all()
            group = (await session.exec(select(ChatGroup))).one()
            group_id = group.id
        await service.execute(ids[0])
        started, release = asyncio.Event(), asyncio.Event()

        async def wait(_):
            started.set()
            await release.wait()

        service.message_interval = 10
        service.sleep = wait
        task = asyncio.create_task(service.execute(ids[1]))
        await asyncio.wait_for(started.wait(), 2)
        lock = service.groups.lock(group_id)
        await asyncio.wait_for(lock.acquire(), 0.5)
        try:
            async with service.database.session_factory() as session:
                group = await session.get(ChatGroup, group_id)
                group.next_message_seq += 1
                session.add(
                    GroupMessage(
                        group_id=group_id,
                        run_id="user-first",
                        seq=group.next_message_seq,
                        sender_type="user",
                        sender_name="选择体验",
                        content="先聊我的事吧。",
                    )
                )
                await session.commit()
        finally:
            lock.release()
            release.set()
        await task
        async with service.database.session_factory() as session:
            messages = (
                await session.exec(
                    select(GroupMessage)
                    .where(GroupMessage.group_id == group_id)
                    .order_by(GroupMessage.seq)
                )
            ).all()
        return [m.sender_type for m in messages]

    assert client.portal.call(scenario) == ["assistant", "user"]


@pytest.mark.asyncio
async def test_existing_database_upgrade_keeps_account_and_builtin_access(tmp_path):
    import sqlite3

    from bingo.db.models import User
    from bingo.db.repositories import RoleRepository
    from bingo.db.session import Database
    from bingo.roles import role_id

    path = tmp_path / "legacy.db"
    database = Database(f"sqlite+aiosqlite:///{path}")
    await database.initialize()
    async with database.session_factory() as session:
        user = User(
            phone="19900112222",
            password_hash="existing-hash",
            username="原用户",
            role_id=role_id("girlfriend"),
        )
        session.add(user)
        await session.commit()
        identifier = user.id
    await database.dispose()
    # Reproduce the deployed users table before this migration.
    with sqlite3.connect(path) as connection:
        connection.execute("ALTER TABLE users DROP COLUMN selective_companions")
        connection.execute("ALTER TABLE users DROP COLUMN companion_selection_complete")
    await database.initialize()
    try:
        async with database.session_factory() as session:
            user = await session.get(User, identifier)
            assert user.username == "原用户"
            assert user.role_id == role_id("girlfriend")
            assert user.companion_selection_complete
            assert not user.selective_companions
            assert len(await RoleRepository(session).list_enabled(identifier)) == 12
    finally:
        await database.dispose()
