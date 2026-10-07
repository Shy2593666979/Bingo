import base64
import json

import pytest

from bingo.agent.model_client import ModelTextDelta
from bingo.schemas.moments import MomentRequest
from bingo.services.moments import narrative_prompt
from tests.api_support import api_payload
from tests.test_role_conversations import client as client
from tests.test_role_conversations import open_role


def test_five_minute_prompt_keeps_story_continuity_and_closes_final_part():
    payload = MomentRequest(
        conversation_id="conversation",
        run_id="part-2",
        previous="小兔子正在回家的路上。",
        closing=True,
    )
    prompt = narrative_prompt(payload)
    assert "999到1221" in prompt
    assert "300秒" in prompt
    assert "不重复开场" in prompt
    assert "小兔子正在回家的路上" in prompt
    assert "不开启新情节" in prompt


def test_moments_have_their_own_api_routes(client):
    from bingo.api import chat, moments

    assert not any(route.path.startswith("/moments/") for route in chat.router.routes)
    assert {route.path for route in moments.router.routes} == {"/moments/stream", "/moments/finish"}
    assert client.get("/openapi.json").json()["paths"]["/api/v1/moments/finish"]["post"][
        "tags"
    ] == ["moments"]


def test_narrative_is_ephemeral_and_does_not_read_chat_or_write_memory(client):
    conversation = open_role(client, "girlfriend")
    captured = []

    async def stream(messages, tools=None):
        captured.append(messages)
        assert tools is None
        yield ModelTextDelta("月光照着小兔子的家。")

    async def synthesize(sentences, output, voice):
        while await sentences.get() is not None:
            await output.put({"type": "audio", "data": base64.b64encode(b"\0\0").decode()})
        await output.put({"type": "audio_done"})

    client.app.state.runtime._llm.stream = stream
    client.app.state.services.chat_speech._synthesize = synthesize
    result = client.post(
        "/api/v1/moments/stream",
        json={
            "conversation_id": conversation,
            "run_id": "story-part-1",
            "seconds": 300,
        },
    )
    assert result.status_code == 200, result.text
    events = [json.loads(line) for line in result.text.splitlines()]
    assert any(event["type"] == "audio" for event in events)
    assert any(event["type"] == "narrative" for event in events)
    assert len(captured[0]) == 2
    assert "女朋友" in captured[0][0].content
    assert api_payload(client.get(f"/api/v1/conversations/{conversation}/messages")) == []
    assert api_payload(client.get("/api/v1/memories")) == []


@pytest.mark.parametrize("feature", ["一起专注", "小约定", "陪我入睡", "今日小记"])
def test_finish_saves_only_one_summary_and_one_sentence_and_is_idempotent(client, feature):
    conversation = open_role(client, "girlfriend")
    calls = []

    async def complete(messages):
        calls.append(messages)
        return "这一会儿我一直陪着你。第二句不应该保留。"

    client.app.state.runtime._llm.complete = complete
    payload = {
        "conversation_id": conversation,
        "session_id": "finished-session",
        "feature": feature,
        "summary": "本次活动已经结束。",
    }
    first = client.post("/api/v1/moments/finish", json=payload)
    repeated = client.post("/api/v1/moments/finish", json=payload)
    assert first.status_code == 200, first.text
    assert api_payload(first) == api_payload(repeated)
    messages = api_payload(client.get(f"/api/v1/conversations/{conversation}/messages"))
    assert len(messages) == 2
    assert messages[0]["content"] == f"[{feature}] 本次活动已经结束。"
    assert messages[1]["content"] == "这一会儿我一直陪着你。"
    assert len(calls) == 1
    assert len(calls[0]) == 2
    assert api_payload(client.get("/api/v1/memories")) == []


def test_moment_endpoints_cannot_use_another_users_conversation(client):
    conversation = open_role(client, "girlfriend")
    account = api_payload(
        client.post(
            "/api/v1/auth/register",
            json={
                "phone": "13900138001",
                "password": "password123",
            },
        )
    )
    client.headers["Authorization"] = f"Bearer {account['access_token']}"
    client.put(
        "/api/v1/me/profile",
        json={
            "username": "新用户",
            "assistant_name": "Bingo",
            "role": "男朋友",
            "personality": "温柔体贴",
        },
    )
    assert (
        client.post(
            "/api/v1/moments/stream",
            json={
                "conversation_id": conversation,
                "run_id": "forbidden",
            },
        ).status_code
        == 404
    )
    assert (
        client.post(
            "/api/v1/moments/finish",
            json={
                "conversation_id": conversation,
                "session_id": "forbidden",
                "feature": "陪我入睡",
                "summary": "结束了。",
            },
        ).status_code
        == 404
    )
