import asyncio
import base64
import json
from collections.abc import AsyncIterator
from datetime import timedelta
from pathlib import Path
from typing import Any, cast

import pytest
from fastapi.testclient import TestClient

from bingo.agent.model_client import (
    ModelMessage,
    ModelStreamEvent,
    ModelTextDelta,
    ModelToolCall,
    ModelToolCalls,
)
from bingo.agent.runtime import AgentRuntime
from bingo.config import Settings
from bingo.db.models import CallInvitation
from bingo.db.time import beijing_now
from bingo.main import create_app
from bingo.services.chat_runs import ChatRunService
from bingo.tools import create_tool_registry
from bingo.tools.base import BaseTool, ToolContext, ToolResult
from bingo.tools.registry import ToolRegistry
from tests.api_support import api_payload


@pytest.fixture
def client(tmp_path: Path) -> TestClient:
    settings = Settings(
        app={"environment": "test"},
        database={"url": f"sqlite+aiosqlite:///{tmp_path / 'test.db'}"},
        model={"provider": "echo"},
        asr={"api_key": ""},
    )
    with TestClient(create_app(settings)) as test_client:
        registration = test_client.post(
            "/api/v1/auth/register",
            json={"phone": "13800138000", "password": "password123"},
        )
        token = api_payload(registration)["access_token"]
        test_client.headers["Authorization"] = f"Bearer {token}"
        test_client.put(
            "/api/v1/me/profile",
            json={
                "username": "测试用户",
                "assistant_name": "Bingo",
                "personality": "理性严谨",
                "role": "同事",
            },
        )
        yield test_client


def test_health(client: TestClient) -> None:
    response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert api_payload(response) == {"status": "ok"}
    assert response.headers["x-request-id"]


def test_image_chat_uses_image_model_and_persists_messages(client: TestClient) -> None:
    image = base64.b64encode(b"\xff\xd8\xff" + bytes(32)).decode("ascii")
    response = client.post(
        "/api/v1/chat",
        json={
            "content": "这是什么？",
            "images": [{"mime_type": "image/jpeg", "data": image}],
        },
    )

    assert response.status_code == 200
    payload = api_payload(response)
    assert payload["content"].startswith("Image received: [")
    assert payload["content"].endswith("] 这是什么？")
    messages = client.get(f"/api/v1/conversations/{payload['conversation_id']}/messages")
    assert messages.status_code == 200
    assert [item["role"] for item in api_payload(messages)] == ["user", "assistant"]
    user_message = api_payload(messages)[0]
    assert user_message["content"] == "这是什么？"
    assert user_message["image_id"]
    image_response = client.get(f"/api/v1/chat/images/{user_message['image_id']}")
    assert image_response.status_code == 200
    assert image_response.content == b"\xff\xd8\xff" + bytes(32)


def test_image_chat_rejects_mime_mismatch(client: TestClient) -> None:
    response = client.post(
        "/api/v1/chat",
        json={
            "images": [
                {
                    "mime_type": "image/png",
                    "data": base64.b64encode(b"not a png").decode("ascii"),
                }
            ],
        },
    )

    assert response.status_code == 422


def test_image_chat_stream_uses_unified_endpoint(client: TestClient) -> None:
    image = base64.b64encode(b"\xff\xd8\xff" + bytes(32)).decode("ascii")
    response = client.post(
        "/api/v1/chat/stream",
        json={
            "content": "",
            "run_id": "image-run-1",
            "images": [{"mime_type": "image/jpeg", "data": image}],
        },
    )

    assert response.status_code == 200
    events = [json.loads(line) for line in response.text.splitlines()]
    assert events[0]["type"] == "start"
    assert events[0]["image_id"]
    reply = "".join(event["content"] for event in events if event["type"] == "segment")
    assert reply.startswith("Image received: [")
    assert events[-1]["type"] == "done"

    removed_endpoint = client.post(
        "/api/v1/chat/image/stream",
        json={"mime_type": "image/jpeg", "image_base64": image},
    )
    assert removed_endpoint.status_code == 404


def test_request_id_is_preserved(client: TestClient) -> None:
    response = client.get("/api/v1/health", headers={"X-Request-ID": "mobile-request-1"})

    assert response.headers["x-request-id"] == "mobile-request-1"


def test_registers_and_deactivates_push_device(client: TestClient) -> None:
    registration = client.put(
        "/api/v1/push/devices",
        json={
            "installation_id": "installation-001",
            "provider": "getui",
            "client_id": "getui-client-id-001",
            "manufacturer": "Xiaomi",
            "model": "test-device",
            "app_version": "0.1.0",
        },
    )

    assert registration.status_code == 200
    assert api_payload(registration)["provider"] == "getui"
    assert api_payload(registration)["active"] is True

    removed = client.delete("/api/v1/push/devices/installation-001")
    assert removed.status_code == 204


def test_asr_reports_missing_configuration(client: TestClient) -> None:
    response = client.post(
        "/api/v1/asr/transcribe",
        content=b"RIFF" + bytes(40),
        headers={"Content-Type": "audio/wav"},
    )

    assert response.status_code == 503
    assert "DashScope" in api_payload(response)["detail"]


def test_profile_options_use_personality_and_role(client: TestClient) -> None:
    response = client.get("/api/v1/profile/options")

    assert response.status_code == 200
    assert "tones" not in api_payload(response)
    assert "温柔体贴" in api_payload(response)["personalities"]
    assert api_payload(response)["roles"] == ["女朋友", "男朋友", "同事", "老师", "家长", "小朋友"]


def test_registration_profile_and_persistent_login(client: TestClient) -> None:
    profile = client.put(
        "/api/v1/me/profile",
        json={
            "username": "小明",
            "assistant_name": "小宾",
            "personality": "温柔体贴",
            "role": "女朋友",
        },
    )
    assert profile.status_code == 200
    assert api_payload(profile)["onboarding_complete"] is True
    assert api_payload(profile)["role"] == "女朋友"

    client.headers.pop("Authorization")
    login = client.post(
        "/api/v1/auth/login",
        json={"phone": "13800138000", "password": "password123"},
    )
    assert login.status_code == 200
    client.headers["Authorization"] = f"Bearer {api_payload(login)['access_token']}"
    assert api_payload(client.get("/api/v1/me"))["assistant_name"] == "小宾"


def test_profile_rejects_role_not_present_in_role_table(client: TestClient) -> None:
    response = client.put(
        "/api/v1/me/profile",
        json={
            "username": "小明",
            "assistant_name": "小宾",
            "personality": "温柔体贴",
            "role": "不存在的角色",
        },
    )

    assert response.status_code == 422


def test_chat_and_history(client: TestClient) -> None:
    response = client.post("/api/v1/chat", json={"content": "hello"})

    assert response.status_code == 200
    body = api_payload(response)
    assert body["content"].startswith("You said: [")
    assert body["content"].endswith("] hello")

    history = client.get(f"/api/v1/conversations/{body['conversation_id']}/messages")
    assert history.status_code == 200
    assert [message["role"] for message in api_payload(history)] == ["user", "assistant"]
    assert [message["status"] for message in api_payload(history)] == ["completed", "completed"]


def test_lists_conversations(client: TestClient) -> None:
    client.post("/api/v1/chat", json={"content": "first topic"})

    response = client.get("/api/v1/conversations")

    assert response.status_code == 200
    assert api_payload(response)[0]["title"] == "first topic"


def test_reuses_single_conversation_when_client_omits_id(client: TestClient) -> None:
    first = client.post("/api/v1/chat", json={"content": "first"})
    second = client.post("/api/v1/chat", json={"content": "second"})

    assert api_payload(second)["conversation_id"] == api_payload(first)["conversation_id"]
    assert len(api_payload(client.get("/api/v1/conversations"))) == 1


def test_conversations_are_isolated_between_users(client: TestClient) -> None:
    client.post("/api/v1/chat", json={"content": "private conversation"})
    second = client.post(
        "/api/v1/auth/register",
        json={"phone": "13900139000", "password": "password456"},
    )
    client.headers["Authorization"] = f"Bearer {api_payload(second)['access_token']}"

    assert api_payload(client.get("/api/v1/conversations")) == []
    assert api_payload(client.get("/api/v1/memories")) == []


def test_http_stream_splits_chat_sentences_and_keeps_paragraphs(
    client: TestClient,
) -> None:
    response = client.post(
        "/api/v1/chat/stream",
        json={"content": "版本 1.2.3。Second? Third!\n换行结束\n最后一段"},
    )
    events = [json.loads(line) for line in response.text.splitlines()]

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/x-ndjson")
    assert [event["type"] for event in events] == [
        "start",
        "segment",
        "segment",
        "segment",
        "segment",
        "segment",
        "done",
    ]
    assert events[1]["content"].startswith("You said: [")
    assert events[1]["content"].endswith("] 版本 1.2.3。")
    assert [event["content"] for event in events[2:-1]] == [
        "Second?",
        "Third!",
        "换行结束",
        "最后一段",
    ]
    assert events[0]["user_message_id"]
    assert events[0]["created_at"].endswith("+08:00")
    assert events[-1]["message_id"]
    assert events[-1]["created_at"].endswith("+08:00")
    assert "assistant_role" in events[-1]


def test_explicit_memory_can_be_listed_and_deleted(client: TestClient) -> None:
    client.post("/api/v1/chat", json={"content": "记住：我喜欢浅烘咖啡"})

    memories = client.get("/api/v1/memories")
    assert memories.status_code == 200
    assert api_payload(memories)[0]["content"] == "我喜欢浅烘咖啡"

    deleted = client.delete(f"/api/v1/memories/{api_payload(memories)[0]['id']}")
    assert deleted.status_code == 204
    assert api_payload(client.get("/api/v1/memories")) == []


def test_rejects_empty_message(client: TestClient) -> None:
    response = client.post("/api/v1/chat", json={"content": ""})

    assert response.status_code == 422


@pytest.mark.parametrize("mode", ["complete", "stream", "spoken"])
def test_assistant_dash_cleanup_is_shared_by_response_history_and_speech(client, mode):
    from bingo.services.chat_speech import ChatSpeechService

    chunks = ["抱抱你—", "—今天辛苦了。\n ", "——", "——\n慢慢聊。"]
    spoken = []

    class Model:
        async def complete(self, messages):
            return "".join(chunks)

        async def stream(self, messages, tools=None):
            for chunk in chunks:
                yield ModelTextDelta(chunk)

    runtime = AgentRuntime(
        Model(), ToolRegistry(), assistant_name="Bingo", persona="温柔", timezone="Asia/Shanghai"
    )
    client.app.state.runtime = runtime
    client.app.state.chat_runs = ChatRunService(client.app.state.database.session_factory, runtime)
    speech = ChatSpeechService(None)

    async def synthesize(sentences, output, voice):
        while (item := await sentences.get()) is not None:
            spoken.append(item["text"])
            await output.put({"type": "audio_segment_done", "segment_index": item["segment_index"]})
        await output.put({"type": "audio_done"})

    speech._synthesize = synthesize
    client.app.state.services.chat_speech = speech
    user_text = "我说的是————这个"
    response = client.post(
        "/api/v1/chat" if mode == "complete" else "/api/v1/chat/stream",
        json={"content": user_text, "read_aloud": mode == "spoken"},
    )
    assert response.status_code == 200
    expected = "抱抱你，今天辛苦了。\n慢慢聊。"
    if mode == "complete":
        result = api_payload(response)
        assert result["content"] == expected
        conversation_id = result["conversation_id"]
    else:
        events = [json.loads(line) for line in response.text.splitlines()]
        conversation_id = events[0]["conversation_id"]
        assert [event["content"] for event in events if event["type"] == "segment"] == [
            "抱抱你，今天辛苦了。",
            "慢慢聊。",
        ]
    history = api_payload(client.get(f"/api/v1/conversations/{conversation_id}/messages"))
    assert [(message["role"], message["content"]) for message in history] == [
        ("user", user_text),
        ("assistant", expected),
    ]
    if mode == "spoken":
        assert spoken == ["抱抱你，今天辛苦了。", "慢慢聊。"]


def test_separator_only_reply_does_not_create_an_empty_assistant_bubble(client):
    class Model:
        async def stream(self, messages, tools=None):
            yield ModelTextDelta("——")
            yield ModelTextDelta("——\n")

    runtime = AgentRuntime(
        Model(), ToolRegistry(), assistant_name="Bingo", persona="温柔", timezone="Asia/Shanghai"
    )
    client.app.state.runtime = runtime
    client.app.state.chat_runs = ChatRunService(client.app.state.database.session_factory, runtime)
    response = client.post("/api/v1/chat/stream", json={"content": "你好"})
    events = [json.loads(line) for line in response.text.splitlines()]
    assert [event["type"] for event in events] == ["start", "error"]
    history = api_payload(
        client.get(f"/api/v1/conversations/{events[0]['conversation_id']}/messages")
    )
    assert [message["role"] for message in history] == ["user"]


class _NoopTool(BaseTool):
    name = "noop"
    description = "Return a fixed result."
    parameters: dict[str, Any] = {
        "type": "object",
        "properties": {},
        "additionalProperties": False,
    }

    async def run(self, context: ToolContext, **arguments: Any) -> ToolResult:
        return ToolResult(content="ok")


class _AlarmModelClient:
    async def complete(self, messages: list[ModelMessage]) -> str:
        return "unused"

    async def stream(
        self,
        messages: list[ModelMessage],
        tools: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[ModelStreamEvent]:
        if any(message.role == "tool" for message in messages):
            yield ModelTextDelta("已提交闹钟请求，等待你确认。")
            return
        yield ModelToolCalls(
            (
                ModelToolCall(
                    call_id="alarm-call-1",
                    name="device_alarm_create",
                    arguments=json.dumps(
                        {
                            "scheduled_at": "2099-01-01T07:00:00+08:00",
                            "label": "起床",
                            "recurrence": "none",
                        },
                        ensure_ascii=False,
                    ),
                ),
            )
        )


class _CallInviteModelClient:
    async def complete(self, messages: list[ModelMessage]) -> str:
        return "unused"

    async def stream(
        self,
        messages: list[ModelMessage],
        tools: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[ModelStreamEvent]:
        if any(message.role == "tool" for message in messages):
            yield ModelTextDelta("我给你打过来啦，接一下吧。")
            return
        assert tools is not None
        assert any(item["function"]["name"] == "assistant_call_invite" for item in tools)
        yield ModelToolCalls(
            (
                ModelToolCall(
                    call_id="call-invite-1",
                    name="assistant_call_invite",
                    arguments=json.dumps({"reason": "想听听你的声音"}, ensure_ascii=False),
                ),
            )
        )


def test_tool_registry_rejects_duplicates_and_bad_arguments() -> None:
    with pytest.raises(ValueError, match="Duplicate tool name"):
        ToolRegistry([_NoopTool(), _NoopTool()])


@pytest.mark.asyncio
async def test_tool_registry_reports_bad_arguments() -> None:
    registry = ToolRegistry([_NoopTool()])
    result = await registry.execute("noop", "not-json", cast(ToolContext, None))
    assert "工具参数错误" in result.content


def test_alarm_tool_streams_approval_and_enforces_state(client: TestClient) -> None:
    client.app.state.runtime = AgentRuntime(
        _AlarmModelClient(),
        create_tool_registry(),
        assistant_name="Bingo",
        persona="可靠",
        timezone="Asia/Shanghai",
    )
    client.app.state.chat_runs = ChatRunService(
        client.app.state.database.session_factory,
        client.app.state.runtime,
    )

    response = client.post("/api/v1/chat/stream", json={"content": "明早七点叫我"})
    events = [json.loads(line) for line in response.text.splitlines()]

    assert response.status_code == 200
    assert [event["type"] for event in events] == [
        "start",
        "approval_required",
        "segment",
        "done",
    ]
    approval = events[1]
    assert approval["tool"] == "device_alarm_create"
    assert approval["arguments"]["label"] == "起床"

    action_id = approval["action_id"]
    approved = client.post(f"/api/v1/device-actions/{action_id}/approve")
    assert approved.status_code == 200
    assert api_payload(approved)["status"] == "approved"

    repeated = client.post(f"/api/v1/device-actions/{action_id}/approve")
    assert repeated.status_code == 200
    assert api_payload(repeated)["status"] == "approved"

    completed = client.post(
        f"/api/v1/device-actions/{action_id}/complete",
        json={"status": "succeeded", "result": "alarm UI opened"},
    )
    assert completed.status_code == 200
    assert api_payload(completed)["status"] == "succeeded"


def test_assistant_can_invite_user_to_realtime_call(client: TestClient) -> None:
    client.app.state.runtime = AgentRuntime(
        _CallInviteModelClient(),
        create_tool_registry(),
        assistant_name="Bingo",
        persona="可靠",
        timezone="Asia/Shanghai",
    )
    client.app.state.chat_runs = ChatRunService(
        client.app.state.database.session_factory,
        client.app.state.runtime,
    )

    response = client.post(
        "/api/v1/chat/stream",
        json={"content": "你怎么不给我打电话？"},
    )
    events = [json.loads(line) for line in response.text.splitlines()]

    assert response.status_code == 200
    invitation = next(event for event in events if event["type"] == "incoming_call")
    assert invitation["caller_name"] == "同事"
    assert invitation["caller_role"] == "同事"
    assert invitation["reason"] == "想听听你的声音"
    assert invitation["status"] == "ringing"

    pending = client.get("/api/v1/call-invitations/pending")
    assert pending.status_code == 200
    assert api_payload(pending)["id"] == invitation["call_id"]

    accepted = client.post(f"/api/v1/call-invitations/{invitation['call_id']}/accept")
    assert accepted.status_code == 200
    assert api_payload(accepted)["status"] == "accepted"
    assert api_payload(client.get("/api/v1/call-invitations/pending")) is None


def test_expired_call_creates_one_missed_call_record(client: TestClient) -> None:
    client.app.state.runtime = AgentRuntime(
        _CallInviteModelClient(),
        create_tool_registry(),
        assistant_name="Bingo",
        persona="可靠",
        timezone="Asia/Shanghai",
    )
    client.app.state.chat_runs = ChatRunService(
        client.app.state.database.session_factory,
        client.app.state.runtime,
    )
    response = client.post(
        "/api/v1/chat/stream",
        json={"content": "给我打个电话"},
    )
    events = [json.loads(line) for line in response.text.splitlines()]
    invitation = next(event for event in events if event["type"] == "incoming_call")

    async def expire_invitation() -> None:
        async with client.app.state.database.session_factory() as session:
            stored = await session.get(CallInvitation, invitation["call_id"])
            assert stored is not None
            stored.expires_at = beijing_now() - timedelta(seconds=1)
            await session.commit()

    asyncio.run(expire_invitation())

    missed = client.post(f"/api/v1/call-invitations/{invitation['call_id']}/miss")
    assert missed.status_code == 204
    repeated = client.post(f"/api/v1/call-invitations/{invitation['call_id']}/miss")
    assert repeated.status_code == 204

    messages = api_payload(
        client.get(f"/api/v1/conversations/{invitation['conversation_id']}/messages")
    )
    missed_calls = [
        message
        for message in messages
        if message["message_type"] == "call" and message["call_status"] == "missed"
    ]
    assert len(missed_calls) == 1
    assert missed_calls[0]["role"] == "assistant"
