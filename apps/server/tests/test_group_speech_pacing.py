import asyncio
import base64
import json
from datetime import datetime

import pytest
from sqlalchemy import create_engine
from sqlmodel import select

from bingo.db.models import Role
from bingo.db.models.groups import ChatGroup, GroupMessage
from bingo.db.session import _upgrade_chat_settings
from bingo.services.chat_speech import ChatSpeechService
from bingo.services.group_chat import GroupChatService
from tests.api_support import api_payload
from tests.test_group_chat import P, create, wait
from tests.test_group_chat import group_app as group_app
from tests.test_group_v2 import v2 as v2


def test_auto_speech_setting_is_per_group_and_persisted(group_app):
    client, ((headers, _), (other, _)), roles, _ = group_app
    one = create(client, headers, roles[:2])
    two = create(client, headers, roles[:2])
    assert one["read_aloud"] is True and two["read_aloud"] is True
    path = P + f"/groups/{one['id']}"
    assert (
        api_payload(client.patch(path, headers=headers, json={"read_aloud": False}))["read_aloud"]
        is False
    )
    assert api_payload(client.get(path, headers=headers))["read_aloud"] is False
    assert (
        api_payload(client.get(P + f"/groups/{two['id']}", headers=headers))["read_aloud"] is True
    )
    assert client.patch(path, headers=other, json={"read_aloud": False}).status_code == 404

    async def stored():
        async with client.app.state.database.session_factory() as session:
            assert (await session.get(ChatGroup, one["id"])).read_aloud is False

    client.portal.call(stored)
    assert (
        api_payload(client.patch(path, headers=headers, json={"read_aloud": False}))["read_aloud"]
        is False
    )


def test_existing_sqlite_groups_without_sound_setting_upgrade_with_sound_on():
    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        connection.exec_driver_sql("CREATE TABLE conversations (id TEXT PRIMARY KEY)")
        connection.exec_driver_sql("CREATE TABLE chat_groups (id TEXT PRIMARY KEY)")
        connection.exec_driver_sql("INSERT INTO chat_groups (id) VALUES ('old-group')")
        _upgrade_chat_settings(connection)
        _upgrade_chat_settings(connection)
        assert (
            connection.exec_driver_sql(
                "SELECT read_aloud FROM chat_groups WHERE id='old-group'"
            ).scalar()
            == 1
        )
        connection.exec_driver_sql("UPDATE chat_groups SET read_aloud=0 WHERE id='old-group'")
        _upgrade_chat_settings(connection)
        assert (
            connection.exec_driver_sql(
                "SELECT read_aloud FROM chat_groups WHERE id='old-group'"
            ).scalar()
            == 0
        )
    engine.dispose()


def test_production_interval_and_parallel_messages_spaced_at_least_1500ms(v2):
    client, ((headers, _), _), roles, _ = v2
    service = client.app.state.services.group_chat
    assert GroupChatService(None, None).message_interval_seconds == 1.5
    service.message_interval_seconds = 1.5
    group = create(client, headers, roles[:3])
    api_payload(
        client.patch(P + f"/groups/{group['id']}", headers=headers, json={"allow_ai_to_ai": False})
    )
    api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=headers,
            json={
                "content": "@全部搭子 一起说吧",
                "mentionAll": True,
                "clientMessageId": "paced-all-001",
            },
        )
    )
    wait(client)
    messages = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    ai = [m for m in messages if m["sender_type"] == "assistant"]
    assert len(ai) == 3
    times = [datetime.fromisoformat(m["created_at"]) for m in ai]
    assert all((b - a).total_seconds() >= 1.5 for a, b in zip(times, times[1:], strict=False))


def test_group_speech_uses_persisted_body_and_role_voice_with_owner_check(v2, monkeypatch):
    client, ((headers, _), (other, _)), roles, _ = v2
    group = create(client, headers, roles[:2])
    api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=headers,
            json={"content": "你好", "clientMessageId": "speech-source-001"},
        )
    )
    wait(client)
    rows = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    message = next(m for m in rows if m["sender_type"] == "assistant")

    async def set_voice():
        async with client.app.state.database.session_factory() as session:
            role = await session.get(Role, message["sender_role_id"])
            role.voice = "role-specific-test-voice"
            await session.commit()

    client.portal.call(set_voice)
    calls = []

    async def speech(text, voice):
        calls.append((text, voice))
        yield {
            "type": "audio",
            "data": base64.b64encode(b"\x01\x02").decode(),
            "sample_rate": 24000,
        }
        yield {"type": "audio_done"}

    monkeypatch.setattr(client.app.state.services.chat_speech, "message_events", speech)
    route = P + f"/groups/{group['id']}/messages/{message['id']}/speech"
    result = client.post(route, headers=headers, json={"text": "不能替换正文"})
    assert result.status_code == 200
    assert [json.loads(line)["type"] for line in result.text.splitlines()] == [
        "audio",
        "audio_done",
    ]
    assert calls == [(message["content"], "role-specific-test-voice")]
    assert client.post(route, headers=other).status_code == 404
    assert client.post(route).status_code == 401
    human = next(m for m in rows if m["sender_type"] == "user")
    assert (
        client.post(
            P + f"/groups/{group['id']}/messages/{human['id']}/speech", headers=headers
        ).status_code
        == 422
    )
    another = create(client, headers, roles[:2])
    assert (
        client.post(
            P + f"/groups/{another['id']}/messages/{message['id']}/speech", headers=headers
        ).status_code
        == 404
    )


def test_cancel_during_pacing_wait_never_publishes_queued_bubbles(v2):
    client, ((headers, _), _), roles, _ = v2
    service = client.app.state.services.group_chat
    service.message_interval_seconds = 1.5
    group = create(client, headers, roles[:3])
    result = api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=headers,
            json={
                "content": "@全部搭子 说句话",
                "mentionAll": True,
                "clientMessageId": "cancel-paced-all",
            },
        )
    )

    async def first_visible():
        async with asyncio.timeout(5):
            while True:
                async with client.app.state.database.session_factory() as session:
                    ai = (
                        await session.exec(
                            select(GroupMessage).where(
                                GroupMessage.group_id == group["id"],
                                GroupMessage.sender_type == "assistant",
                            )
                        )
                    ).all()
                if ai:
                    return
                await asyncio.sleep(0.01)

    client.portal.call(first_visible)
    assert (
        client.post(
            P + f"/groups/{group['id']}/runs/{result['run_id']}/cancel", headers=headers
        ).status_code
        == 204
    )
    wait(client)
    rows = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    assert len([m for m in rows if m["sender_type"] == "assistant"]) == 1


@pytest.mark.asyncio
async def test_stopping_message_audio_closes_provider_task():
    service = ChatSpeechService(None)
    closed = asyncio.Event()

    async def synth(sentences, output, voice):
        try:
            assert await sentences.get() == "抱抱，今天辛苦了。"
            await output.put({"type": "audio", "data": "AQI="})
            await asyncio.Event().wait()
        finally:
            closed.set()

    service._synthesize = synth
    stream = service.message_events("抱抱，今天辛苦了。", "test-voice")
    assert (await anext(stream))["type"] == "audio"
    await stream.aclose()
    assert closed.is_set()
