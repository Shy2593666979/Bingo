import asyncio
import base64
from types import SimpleNamespace

import pytest
from sqlmodel import select
from starlette.websockets import WebSocketDisconnect

from bingo.db.models.groups import GroupCall
from bingo.services.group_call import GroupCallSession
from tests.api_support import api_payload
from tests.test_group_chat import P, create, group_app, wait  # noqa: F401, F811


def role(identifier):
    return SimpleNamespace(
        id=identifier, nickname=identifier, context_prompt="自然聊天", voice=identifier
    )


class Speech:
    def __init__(self):
        self.voices = []

    async def message_events(self, text, voice):
        self.voices.append(voice)
        yield {"type": "audio", "data": base64.b64encode(b"\0" * 480).decode()}
        yield {"type": "audio_done"}


def test_ai_handoff_requires_an_invitation_and_broadcast_excludes_self():
    session = GroupCallSession(
        roles=[role("甜甜"), role("暖暖")], model=None, speech=None, emit=None
    )
    assert session.targets("暖暖说得有道理", exclude="甜甜") == ([], False)
    assert session.targets("不要@暖暖", exclude="甜甜") == ([], False)
    targets, strong = session.targets("@全体搭子 来说一句吧", exclude="甜甜")
    assert strong and [r.id for r in targets] == ["暖暖"]
    targets, strong = session.targets("@暖暖 你来说一句吧", exclude="甜甜")
    assert strong and [r.id for r in targets] == ["暖暖"]


@pytest.mark.asyncio
async def test_parallel_preparation_first_ready_and_playback_ack(monkeypatch):
    import bingo.services.group_call as module

    real_sleep = asyncio.sleep
    events, speech = [], Speech()

    async def sleep(seconds):
        await real_sleep(0 if seconds == 1.5 else seconds)

    monkeypatch.setattr(module.asyncio, "sleep", sleep)

    class Model:
        async def complete(self, messages):
            if "你是慢。" in messages[0].content:
                await real_sleep(0.04)
            return "你好"

    async def emit(event):
        events.append(event)

    session = GroupCallSession(
        roles=[role("慢"), role("快")], model=Model(), speech=speech, emit=emit
    )
    task = asyncio.create_task(session.respond("@全部搭子"))
    for _ in range(100):
        if any(e["type"] == "audio_end" for e in events):
            break
        await real_sleep(0.002)
    assert [e["role_id"] for e in events if e["type"] == "speaker"] == ["快"]
    # No second speaker until the client confirms actual playback, even when ready.
    await real_sleep(0.06)
    assert len([e for e in events if e["type"] == "speaker"]) == 1
    session.acknowledge("stale-id")
    assert not session.played.is_set()
    session.acknowledge(session.utterance)
    for _ in range(100):
        if len([e for e in events if e["type"] == "audio_end"]) == 2:
            break
        await real_sleep(0.002)
    session.acknowledge(session.utterance)
    await asyncio.wait_for(task, 1)
    assert speech.voices == ["快", "慢"]
    assert [row["name"] for row in session.call_log] == ["快", "慢"]


@pytest.mark.asyncio
async def test_speech_interrupt_cancels_inflight_model_and_old_audio():
    cancelled = asyncio.Event()

    class Model:
        async def complete(self, messages):
            try:
                await asyncio.Event().wait()
            finally:
                cancelled.set()

    events = []

    async def emit(event):
        events.append(event)

    session = GroupCallSession(roles=[role("甜甜")], model=Model(), speech=Speech(), emit=emit)
    session.task = asyncio.create_task(session.respond("你好"))
    await asyncio.sleep(0.01)
    await session.partial("等一下")
    await asyncio.wait_for(cancelled.wait(), 0.5)
    assert session.generation == 1
    assert events[-1]["type"] == "interrupted"
    assert not any(e["type"] == "audio" for e in events)
    await session.close()


def test_group_call_auth_membership_and_record(group_app, monkeypatch):  # noqa: F811
    from bingo.api import group_calls

    client, ((headers, user), (other, _)), roles, _ = group_app
    group = create(client, headers, roles[:2])
    url = P + f"/groups/{group['id']}/calls/stream?role_id={roles[0]['id']}"
    for auth_headers, suffix in [
        ({}, ""),
        (other, ""),
        (headers, f"&role_id={roles[2]['id']}"),
        (headers, f"&role_id={roles[0]['id']}"),
    ]:
        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect(url + suffix, headers=auth_headers):
                pass
    client.app.state.settings.asr.api_key = "test"
    client.app.state.settings.realtime_call.api_key = "test"

    async def proxy(self, bridge, **kwargs):
        await bridge.send_json({"type": "ready"})
        await bridge.receive()

    monkeypatch.setattr(group_calls.RealtimeAsrProxy, "run", proxy)
    with client.websocket_connect(url, headers=headers) as ws:
        assert ws.receive_json()["type"] == "ready"
        ws.send_json({"type": "hangup"})
        assert ws.receive_json()["type"] == "ended"

    async def saved():
        async with client.app.state.database.session_factory() as session:
            calls = (await session.exec(select(GroupCall))).all()
            assert len(calls) == 1 and calls[0].status == "ended"
            assert calls[0].user_id == user

    client.portal.call(saved)
    rows = api_payload(client.get(P + f"/groups/{group['id']}/messages", headers=headers))
    assert rows[-1]["sender_type"] == "system" and "群聊电话未接通" in rows[-1]["content"]


def test_group_media_persist_access_and_model_context(group_app):  # noqa: F811
    client, ((headers, _), (other, _)), roles, model = group_app
    group = create(client, headers, roles[:2])
    png = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"0" * 20).decode()
    path = P + f"/groups/{group['id']}"
    body = {
        "clientMessageId": "group-image-001",
        "content": "[图片]",
        "images": [{"mime_type": "image/png", "data": png}],
    }
    response = client.post(path + "/chat", headers=headers, json=body)
    assert response.status_code == 200
    wait(client)
    rows = api_payload(client.get(path + "/messages", headers=headers))
    message = next(m for m in rows if m["sender_type"] == "user")
    assert message["attachment"]["type"] == "image"
    image_path = path + f"/messages/{message['id']}/image"
    assert client.get(image_path, headers=headers).content == base64.b64decode(png)
    assert client.get(image_path, headers=other).status_code == 404
    assert any(m.image_data_urls for context in model.contexts for m in context)
    location = {"name": "公园", "address": "测试公园", "longitude": 116.4, "latitude": 39.9}
    assert (
        client.post(
            path + "/chat",
            headers=headers,
            json={
                "clientMessageId": "group-location-001",
                "content": "[位置] 公园",
                "location": location,
            },
        ).status_code
        == 200
    )
    wait(client)
    rows = api_payload(client.get(path + "/messages", headers=headers))
    assert any(
        m.get("attachment", {}).get("type") == "location" for m in rows if m.get("attachment")
    )


def test_discussion_commands_validate_and_persist_summary(group_app, monkeypatch):  # noqa: F811
    import json

    from bingo.api import group_calls

    client, ((headers, _), _), roles, _ = group_app
    group = create(client, headers, roles[:2])
    client.app.state.settings.asr.api_key = "test"
    client.app.state.settings.realtime_call.api_key = "test"

    async def proxy(self, bridge, **kwargs):
        await bridge.send_json({"type": "ready"})
        await bridge.receive()

    monkeypatch.setattr(group_calls.RealtimeAsrProxy, "run", proxy)
    url = P + f"/groups/{group['id']}/calls/stream?role_id={roles[0]['id']}"
    with client.websocket_connect(url, headers=headers) as ws:
        assert ws.receive_json()["type"] == "ready"
        ws.send_json({"type": "set_discussion_config", "max_silent_turns": True})
        assert ws.receive_json()["type"] == "command_error"
        ws.send_json({"type": "set_discussion_config", "max_silent_turns": 50})
        assert ws.receive_json()["type"] == "command_error"
        ws.send_json({"type": "resume_discussion"})
        assert ws.receive_json()["type"] == "command_error"
        ws.send_json({"type": "pause_discussion"})
        assert ws.receive_json()["type"] == "command_error"
        ws.send_json({"type": "hangup"})
        assert ws.receive_json()["type"] == "ended"

    async def saved():
        async with client.app.state.database.session_factory() as session:
            call = (await session.exec(select(GroupCall))).one()
            summary = json.loads(call.transcript_json)[-1]
            assert summary["type"] == "discussion_summary"
            assert summary["discussion"]["phase"] == "closed"
            assert summary["discussion"]["max_silent_turns"] == 30
            assert summary["metrics"]["model_requests"] == 0

    client.portal.call(saved)
