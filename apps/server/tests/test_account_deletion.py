import sqlite3
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event

from bingo.background.service import EngagementService
from bingo.config import Settings
from bingo.db.models import (
    CallInvitation,
    Conversation,
    DeviceAction,
    Memory,
    MemoryCheckpoint,
    Message,
    MorningGreeting,
    ProactiveMessage,
    PushDevice,
    PushOutbox,
    Role,
    RolePreference,
    VoiceJob,
)
from bingo.db.time import beijing_now
from bingo.main import create_app
from bingo.services import account_deletion
from tests.api_support import api_payload


@pytest.fixture
def account_client(tmp_path):
    path = tmp_path / "accounts.db"
    app = create_app(
        Settings(
            app={"environment": "test"},
            database={"url": f"sqlite+aiosqlite:///{path}"},
        )
    )
    with TestClient(app) as client:

        def enable_foreign_keys(connection, *_):
            cursor = connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

        event.listen(app.state.database.engine.sync_engine, "checkout", enable_foreign_keys)
        if app.state.engagement is None:
            app.state.engagement = EngagementService(
                app.state.database.session_factory,
                object(),
                redis_url=None,
                follow_up_delays=(3600,),
                recommendation_delay=18000,
                poll_seconds=1,
            )
            app.state.services.engagement = app.state.engagement
        account = api_payload(
            client.post(
                "/api/v1/auth/register",
                json={
                    "phone": "13800138000",
                    "password": "original123",
                },
            )
        )
        client.headers["Authorization"] = "Bearer " + account["access_token"]
        yield client, account["user"]["id"], path


def test_requires_login_and_explicit_confirmation(account_client):
    client, _, _ = account_client
    assert client.request("DELETE", "/api/v1/me/account", json={}).status_code == 422
    assert (
        client.request("DELETE", "/api/v1/me/account", json={"confirmed": False}).status_code == 422
    )
    assert client.get("/api/v1/me").status_code == 200
    client.headers.pop("Authorization")
    assert client.request("DELETE", "/api/v1/me/account", json={"confirmed": True}).status_code in {
        401,
        403,
    }


def test_deletes_own_data_revokes_sessions_and_preserves_other_accounts(
    account_client, monkeypatch, tmp_path
):
    client, user_id, path = account_client
    other = api_payload(
        client.post(
            "/api/v1/auth/register",
            json={
                "phone": "13800138001",
                "password": "otherpassword",
            },
        )
    )
    extra_session = api_payload(
        client.post(
            "/api/v1/auth/login",
            json={
                "phone": "13800138000",
                "password": "original123",
            },
        )
    )["access_token"]
    image_id = str(uuid4())
    images = tmp_path / "images"
    images.mkdir()
    image = images / f"{image_id}.jpg"
    image.write_bytes(b"image")
    monkeypatch.setattr(account_deletion, "IMAGE_DIRECTORY", images)
    scheduled = []
    monkeypatch.setattr(client.app.state.voice_cloning, "schedule", scheduled.append)

    async def seed():
        async with client.app.state.database.session_factory() as session:
            role = Role(
                code="custom-delete-test",
                name="custom-delete-test",
                avatar="custom",
                owner_id=user_id,
                voice="owned-voice",
                owned_voice="owned-voice",
                avatar_data="private-avatar",
                prompt="private",
            )
            session.add(role)
            await session.commit()
            conversation = Conversation(user_id=user_id, role_id=role.id)
            other_conversation = Conversation(user_id=other["user"]["id"])
            session.add_all([conversation, other_conversation])
            await session.commit()
            message = Message(
                conversation_id=conversation.id,
                role="assistant",
                content="private",
                image_id=image_id,
            )
            session.add(message)
            session.add(Message(conversation_id=other_conversation.id, role="user", content="keep"))
            await session.commit()
            proactive = ProactiveMessage(
                user_id=user_id, conversation_id=conversation.id, message_id=message.id
            )
            device = PushDevice(
                user_id=user_id,
                installation_id="delete-device",
                provider="getui",
                client_id="private-cid",
            )
            session.add_all([proactive, device])
            await session.commit()
            session.add_all(
                [
                    PushOutbox(
                        user_id=user_id,
                        device_id=device.id,
                        proactive_message_id=proactive.id,
                        title="private",
                        body="private",
                        payload_json="{}",
                    ),
                    MorningGreeting(
                        user_id=user_id,
                        conversation_id=conversation.id,
                        partner_key=role.id,
                        greeting_date="2026-10-11",
                        scheduled_at=beijing_now(),
                    ),
                    CallInvitation(
                        user_id=user_id,
                        conversation_id=conversation.id,
                        role_id=role.id,
                        caller_name="private",
                        expires_at=beijing_now(),
                    ),
                    Memory(user_id=user_id, role_id=role.id, content="private"),
                    MemoryCheckpoint(
                        user_id=user_id,
                        role_id=role.id,
                        conversation_id=conversation.id,
                        last_message_id=message.id,
                    ),
                    DeviceAction(user_id=user_id, tool_name="alarm", arguments_json="{}"),
                    RolePreference(user_id=user_id, role_id=role.id, personality="private"),
                    VoiceJob(
                        user_id=user_id,
                        role_id=role.id,
                        status="pending",
                        sample="private-audio",
                        sample_token="private-token",
                    ),
                ]
            )
            await session.commit()
            await client.app.state.engagement.record_user_activity(user_id, conversation.id)
            await client.app.state.engagement._broker.save_recommendations(
                f"{user_id}:{conversation.id}", ["private recommendation"]
            )
            return conversation.id

    conversation_id = client.portal.call(seed)
    response = client.request("DELETE", "/api/v1/me/account", json={"confirmed": True})
    assert response.status_code == 204
    assert response.content == b""
    assert client.get("/api/v1/me").status_code == 401
    client.headers["Authorization"] = "Bearer " + extra_session
    assert client.get("/api/v1/me").status_code == 401
    assert (
        client.post(
            "/api/v1/auth/login",
            json={
                "phone": "13800138000",
                "password": "original123",
            },
        ).status_code
        == 401
    )
    client.headers["Authorization"] = "Bearer " + other["access_token"]
    assert client.get("/api/v1/me").status_code == 200
    assert not image.exists()
    with sqlite3.connect(path) as database:
        for table in [
            "users",
            "auth_sessions",
            "conversations",
            "memories",
            "memory_checkpoints",
            "morning_greetings",
            "call_invitations",
            "device_actions",
            "proactive_messages",
            "push_devices",
            "push_outbox",
            "role_preferences",
            "voice_jobs",
        ]:
            column = "id" if table == "users" else "user_id"
            assert (
                database.execute(
                    f"SELECT COUNT(*) FROM {table} WHERE {column}=?", (user_id,)
                ).fetchone()[0]
                == 0
            )
        assert (
            database.execute("SELECT COUNT(*) FROM roles WHERE owner_id=?", (user_id,)).fetchone()[
                0
            ]
            == 0
        )
        assert (
            database.execute("SELECT COUNT(*) FROM roles WHERE owner_id IS NULL").fetchone()[0] == 6
        )
        assert database.execute("SELECT content FROM messages").fetchall() == [("keep",)]
        cleanups = database.execute(
            "SELECT user_id, role_id, kind, sample, sample_token FROM voice_jobs"
        ).fetchall()
        assert len(cleanups) == 2
        assert all(
            row[0:2] == ("deleted", "deleted") and row[3:] == (None, None) for row in cleanups
        )
    assert len(scheduled) == 2
    assert (
        client.portal.call(
            client.app.state.engagement._broker.get_recommendations,
            f"{user_id}:{conversation_id}",
        )
        == []
    )


def test_cleanup_failure_does_not_report_success_or_delete_account(account_client, monkeypatch):
    client, _, _ = account_client

    async def unavailable(*args):
        raise RuntimeError("cache unavailable")

    monkeypatch.setattr(client.app.state.engagement, "forget_user", unavailable)
    with pytest.raises(RuntimeError, match="cache unavailable"):
        client.request("DELETE", "/api/v1/me/account", json={"confirmed": True})
    assert client.get("/api/v1/me").status_code == 200
