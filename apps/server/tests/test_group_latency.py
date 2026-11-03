import asyncio
import json

import pytest
from sqlmodel import select

from bingo.agent.model_client import AgentModelClient, create_group_model_client
from bingo.agent.social_runtime import ReplyHeader
from bingo.config import Settings
from bingo.db.models.groups import GroupMessage, GroupRun
from tests.api_support import api_payload
from tests.test_group_chat import P, create, group_app, wait  # noqa: F401
from tests.test_group_v2 import IndependentModel, v2  # noqa: F401


def test_group_ark_uses_fast_model_settings_without_changing_single_chat():
    settings = Settings(
        model={
            "provider": "openai_compat",
            "api_mode": "responses",
            "base_url": "https://ark.cn-beijing.volces.com/api/v3",
            "api_key": "test-only",
        }
    )
    group = create_group_model_client(settings)
    assert group._text_extra_body == {"thinking": {"type": "disabled"}}
    assert group._trust_env is False
    assert group._max_output_tokens == 1024
    assert group._reuse_connections is True
    single = AgentModelClient(settings)
    assert single._text_extra_body is None
    assert single._trust_env is True
    assert settings.model.thinking is None
    settings.model.base_url = "https://example.com/v1"
    assert create_group_model_client(settings)._text_extra_body is None


@pytest.mark.asyncio
async def test_group_reuses_provider_connection_and_closes_it(monkeypatch):
    settings = Settings(
        model={
            "provider": "openai_compat",
            "api_mode": "responses",
            "base_url": "https://ark.cn-beijing.volces.com/api/v3",
            "api_key": "test-only",
        }
    )
    model = create_group_model_client(settings)
    created = []

    class Client:
        closed = False

        async def close(self):
            self.closed = True

    def new_client(options):
        result = Client()
        created.append(result)
        return result

    monkeypatch.setattr(model, "_new_client", new_client)
    async with model._client_session(model._client_options) as first:
        pass
    async with model._client_session(model._client_options) as second:
        pass
    assert first is second
    assert len(created) == 1
    await model.aclose()
    assert first.closed


def test_streamed_header_never_leaks_and_preserves_typed_metadata():
    text = (
        json.dumps(
            {
                "replyToMessageId": "real-message",
                "mentionTargets": [{"type": "user", "id": "real-user"}],
            }
        )
        + "\n你好"
    )
    for payload in (text, "```json\n" + text.split("\n")[0] + "\n```\n你好"):
        header = ReplyHeader()
        assert "".join(header.feed(char) for char in payload) == "你好"
        assert header.intent.reply_to_message_id == "real-message"
        assert header.intent.mention_targets == [{"type": "user", "id": "real-user"}]
    header = ReplyHeader()
    assert header.feed("直接正文") == "直接正文"


def test_all_mentions_skip_every_preflight_decision(request):
    client, ((headers, _), _), roles, model = request.getfixturevalue("v2")
    group = create(client, headers, roles)
    api_payload(
        client.patch(P + f"/groups/{group['id']}", headers=headers, json={"allow_ai_to_ai": False})
    )
    run = api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=headers,
            json={
                "clientMessageId": "no-preflight-all",
                "content": "@全部搭子 你们都在干嘛",
                "mentionAll": True,
            },
        )
    )
    wait(client)
    assert len(model.decisions) == 0
    assert len(model.generations) == 8

    async def stored():
        async with client.app.state.database.session_factory() as session:
            row = await session.get(GroupRun, run["run_id"])
            assert row.decision_calls == 0
            assert row.emitted_ai_messages == 8

    client.portal.call(stored)


def test_ordinary_first_response_does_not_wait_for_optional_decisions(request):
    client, ((headers, _), _), roles, _ = request.getfixturevalue("v2")

    class SlowDecision(IndependentModel):
        def __init__(self):
            super().__init__()
            self.optional_release = asyncio.Event()
            self.body_ready = asyncio.Event()

        async def complete(self, messages):
            if '"action"' in messages[-1].content:
                await self.optional_release.wait()
                return '{"action":"silent"}'
            return "[]"

        async def stream(self, messages, tools=None):
            async for chunk in super().stream(messages, tools):
                yield chunk
            self.body_ready.set()

    model = SlowDecision()
    client.app.state.services.group_chat.model = model
    group = create(client, headers, roles[:3])
    run = api_payload(
        client.post(
            P + f"/groups/{group['id']}/chat",
            headers=headers,
            json={"clientMessageId": "ordinary-no-gate", "content": "你们都在干嘛"},
        )
    )

    async def first_response():
        await asyncio.wait_for(model.body_ready.wait(), 2)
        async with client.app.state.database.session_factory() as session:
            rows = (
                await session.exec(
                    select(GroupMessage).where(
                        GroupMessage.run_id == run["run_id"],
                        GroupMessage.sender_type == "assistant",
                        GroupMessage.content != "",
                    )
                )
            ).all()
            assert len(rows) == 1

    client.portal.call(first_response)
    client.portal.call(model.optional_release.set)
    wait(client)
