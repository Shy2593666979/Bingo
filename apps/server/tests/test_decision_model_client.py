import asyncio
import json
from types import SimpleNamespace

import httpx
import pytest

from bingo.agent.decision_model_client import DecisionModelClient
from bingo.config import DecisionModelSettings
from bingo.services.group_call_scheduler import TurnScheduler


def client(handler):
    return DecisionModelClient(
        DecisionModelSettings(
            endpoint="https://workspace.example/compatible-mode/v1/systemone", api_key="test-key"
        ),
        transport=httpx.MockTransport(handler),
    )


@pytest.mark.asyncio
async def test_required_recipient_cannot_be_replaced_with_finish():
    def handler(request):
        options = json.loads(request.content)["questions"]["next_turn"]["criteria"]
        assert set(options) == {"role-a"}
        return httpx.Response(200, json={"answers": {"next_turn": {"choice": "finish"}}})

    async def fallback(messages):
        return '{"choice":"outsider"}'

    decision = client(handler)
    try:
        with pytest.raises(ValueError, match="No valid routing decision"):
            await decision.choose(
                {"required_recipients": ["role-a"]}, {"role-a": "甲"}, fallback=fallback
            )
    finally:
        await decision.aclose()


@pytest.mark.asyncio
@pytest.mark.parametrize("choice", ["role-a", "wait", "finish"])
async def test_typed_choice_is_one_request_not_chat_generation(choice):
    requests = []

    def handler(request):
        requests.append(request)
        body = json.loads(request.content)
        assert body["model"] == "decision-model-preview"
        assert "messages" not in body
        assert len(body["questions"]) == 1
        assert body["questions"]["next_turn"]["criteria"]["role-a"] == '{"name": "甲"}'
        assert request.headers["authorization"] == "Bearer test-key"
        return httpx.Response(200, json={"answers": {"next_turn": {"choice": choice}}})

    decision = client(handler)
    try:
        assert await decision.choose({"recent": []}, {"role-a": {"name": "甲"}}) == choice
        assert len(requests) == 1
    finally:
        await decision.aclose()


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["timeout", "http", "invalid", "malformed"])
async def test_failures_use_one_validated_generic_fallback(failure):
    def handler(request):
        if failure == "timeout":
            raise httpx.ReadTimeout("timeout", request=request)
        if failure == "http":
            return httpx.Response(503)
        if failure == "malformed":
            return httpx.Response(200, text="not JSON")
        return httpx.Response(200, json={"answers": {"next_turn": {"choice": "outsider"}}})

    calls = []

    async def fallback(messages):
        calls.append(messages)
        return '{"choice":"role-a"}'

    decision = client(handler)
    try:
        assert await decision.choose({}, {"role-a": "甲"}, fallback=fallback) == "role-a"
        assert len(calls) == 1
    finally:
        await decision.aclose()


@pytest.mark.asyncio
async def test_cancelled_decision_never_runs_fallback():
    started = asyncio.Event()

    async def handler(request):
        started.set()
        await asyncio.Event().wait()

    async def fallback(messages):
        pytest.fail("cancelled decision must not restart a model call")

    decision = client(handler)
    task = asyncio.create_task(decision.choose({}, {"role-a": "甲"}, fallback=fallback))
    await started.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    await decision.aclose()


@pytest.mark.asyncio
async def test_call_routes_exact_decision_without_random_reselection():
    class Router:
        async def choose(self, state, candidates, **kwargs):
            assert set(candidates) == {"a", "b"}
            return "b"

    engine = SimpleNamespace(
        roles=[SimpleNamespace(id=i, nickname=i, context_prompt="人物") for i in "ab"],
        history=[],
        decision_model=Router(),
        complete=None,
    )
    state = SimpleNamespace(topic="聊天", topic_summary="", recent_speakers=[], phase="discussing")
    assert (await TurnScheduler().next_turn(engine, state)).speaker_id == "b"
