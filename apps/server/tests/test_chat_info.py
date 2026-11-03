from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlmodel import select

from bingo.config import Settings
from bingo.db.models import Conversation, Memory, Message, ProactiveMessage, User
from bingo.db.repositories import ProactiveMessageRepository, PushDeviceRepository
from bingo.db.session import Database
from bingo.main import create_app
from bingo.push.service import PushService
from tests.api_support import api_payload
from tests.test_push import RecordingPushProvider


@pytest.fixture
def client(tmp_path: Path):
    settings = Settings(
        app={"environment": "test"},
        model={"provider": "echo"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'info.db'}"},
    )
    with TestClient(create_app(settings)) as client:
        result = api_payload(
            client.post(
                "/api/v1/auth/register", json={"phone": "19912345678", "password": "password123"}
            )
        )
        client.headers["Authorization"] = f"Bearer {result['access_token']}"
        yield client


def open_chat(client, index=0):
    roles = api_payload(client.get("/api/v1/roles"))
    return api_payload(client.post(f"/api/v1/roles/{roles[index]['id']}/conversation"))["id"]


def test_settings_partial_save_is_scoped_and_survives_reopen(client):
    first, second = open_chat(client), open_chat(client, 1)
    endpoint = f"/api/v1/conversations/{first}/settings"
    assert api_payload(client.patch(endpoint, json={"pinned": True, "muted": True})) == {
        "pinned": True,
        "muted": True,
    }
    assert api_payload(client.patch(endpoint, json={"muted": False})) == {
        "pinned": True,
        "muted": False,
    }
    assert api_payload(client.get(f"/api/v1/conversations/{second}/settings")) == {
        "pinned": False,
        "muted": False,
    }
    assert open_chat(client) == first
    assert api_payload(client.get(endpoint))["pinned"] is True
    roles = api_payload(client.get("/api/v1/roles"))
    assert next(role for role in roles if role.get("conversation_id") == first)["pinned"] is True


def test_search_and_clear_only_current_chat_and_preserve_memory(client):
    first, second = open_chat(client), open_chat(client, 1)

    async def seed():
        async with client.app.state.database.session_factory() as session:
            user = (await session.exec(select(User))).one()
            for chat in (first, second):
                session.add(Message(conversation_id=chat, role="user", content="今天要100%开心"))
                session.add(Message(conversation_id=chat, role="user", content="另一句消息"))
            session.add(Memory(user_id=user.id, content="喜欢草莓"))
            await session.commit()
            await ProactiveMessageRepository(session, user.id).create(first, "陪你开心", 1)

    client.portal.call(seed)
    endpoint = f"/api/v1/conversations/{first}/messages"
    assert len(api_payload(client.get(endpoint, params={"q": "100%"}))) == 1
    assert api_payload(client.get(endpoint, params={"q": "不存在"})) == []
    assert client.delete(endpoint).status_code == 204
    assert api_payload(client.get(endpoint)) == []
    assert len(api_payload(client.get(f"/api/v1/conversations/{second}/messages"))) == 2

    async def verify():
        async with client.app.state.database.session_factory() as session:
            assert len((await session.exec(select(Memory))).all()) == 1
            assert not (await session.exec(select(ProactiveMessage))).all()

    client.portal.call(verify)


def test_other_account_cannot_read_update_search_or_clear_chat(client):
    chat = open_chat(client)
    registration = api_payload(
        client.post(
            "/api/v1/auth/register", json={"phone": "19912345679", "password": "password123"}
        )
    )
    client.headers["Authorization"] = f"Bearer {registration['access_token']}"
    base = f"/api/v1/conversations/{chat}"
    assert client.get(base + "/settings").status_code == 404
    assert client.patch(base + "/settings", json={"muted": True}).status_code == 404
    assert client.get(base + "/messages", params={"q": "消息"}).status_code == 404
    assert client.delete(base + "/messages").status_code == 404


def test_streaming_chat_cannot_be_cleared(client):
    chat = open_chat(client)

    async def seed():
        async with client.app.state.database.session_factory() as session:
            session.add(
                Message(
                    conversation_id=chat, role="assistant", content="正在回复", status="streaming"
                )
            )
            await session.commit()

    client.portal.call(seed)
    assert client.delete(f"/api/v1/conversations/{chat}/messages").status_code == 409
    assert len(api_payload(client.get(f"/api/v1/conversations/{chat}/messages"))) == 1


@pytest.mark.asyncio
async def test_muting_suppresses_new_and_already_queued_push(tmp_path):
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'mute.db'}")
    await database.initialize()
    provider = RecordingPushProvider()
    service = PushService(database.session_factory, provider, poll_seconds=1)
    try:
        async with database.session_factory() as session:
            user = User(phone="19999999999", password_hash="hash")
            session.add(user)
            await session.flush()
            chat = Conversation(user_id=user.id)
            session.add(chat)
            await session.commit()
            await PushDeviceRepository(session).upsert(
                user_id=user.id,
                installation_id="mute-device",
                provider="getui",
                client_id="mute-client",
                manufacturer=None,
                model=None,
                app_version=None,
            )
            proactive = await ProactiveMessageRepository(session, user.id).create(
                chat.id, "你好", 1
            )
        assert await service.enqueue(proactive, "伙伴", "你好") == 1
        async with database.session_factory() as session:
            current = await session.get(Conversation, chat.id)
            current.muted = True
            await session.commit()
        assert await service.enqueue(proactive, "伙伴", "你好") == 0
        assert await service._deliver_one()
        assert not provider.deliveries
    finally:
        await service.close()
        await database.dispose()
