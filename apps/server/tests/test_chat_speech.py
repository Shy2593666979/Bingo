import asyncio
from types import SimpleNamespace

import pytest

from bingo.services.chat_speech import ChatSpeechService, split_speech_text


def test_speech_splits_inside_a_planning_bubble_and_flushes_tail():
    pieces, tail = split_speech_text("第一天上午：逛博物馆。午饭吃小吃。下午喝茶")
    assert pieces == ["第一天上午：逛博物馆。", "午饭吃小吃。"]
    assert split_speech_text(tail, final=True) == (["下午喝茶"], "")
    assert split_speech_text("甲" * 120) == (["甲" * 100], "甲" * 20)


@pytest.mark.asyncio
async def test_audio_arrives_before_model_finishes_without_changing_bubbles():
    released = asyncio.Event()
    service = ChatSpeechService(None)

    class Subscription:
        async def events(self):
            yield {"type": "start"}
            yield {"type": "text_delta", "content": "第一天上午：逛博物馆。"}
            await released.wait()
            yield {"type": "text_delta", "content": "午饭吃小吃。"}
            yield {"type": "segment", "content": "第一天上午：逛博物馆。午饭吃小吃。"}
            yield {"type": "done"}

    async def synthesize(sentences, output, voice):
        assert voice == "cloned-partner"
        while (sentence := await sentences.get()) is not None:
            await output.put({"type": "audio", "sentence": sentence})
        await output.put({"type": "audio_done"})

    service._synthesize = synthesize
    events = service.events(Subscription(), "user", "run", "cloned-partner")
    assert (await anext(events))["type"] == "start"
    assert (await asyncio.wait_for(anext(events), 1))["sentence"] == "第一天上午：逛博物馆。"
    released.set()
    remaining = [event async for event in events]
    assert (
        next(event for event in remaining if event["type"] == "segment")["content"]
        == "第一天上午：逛博物馆。午饭吃小吃。"
    )
    assert any(event["type"] == "audio_done" for event in remaining)
    assert service.tasks == {}


@pytest.mark.asyncio
async def test_provider_failure_does_not_fail_text_response():
    service = ChatSpeechService(None)

    async def fail(*args):
        raise ValueError("provider unavailable")

    async def events():
        yield {"type": "text_delta", "content": "你好。"}
        yield {"type": "segment", "content": "你好。"}
        yield {"type": "done"}

    service._synthesize = fail
    result = [
        event
        async for event in service.events(SimpleNamespace(events=events), "user", "run", "voice")
    ]
    assert {event["type"] for event in result} == {"segment", "done", "audio_error"}


@pytest.mark.asyncio
async def test_stop_is_account_scoped_and_disconnect_cleans_tasks():
    service = ChatSpeechService(None)
    waiting = asyncio.Event()

    async def events():
        yield {"type": "start"}
        await waiting.wait()

    async def synthesize(*args):
        await asyncio.Event().wait()

    service._synthesize = synthesize
    stream = service.events(SimpleNamespace(events=events), "owner", "run", "voice")
    await anext(stream)
    await service.stop("other", "run")
    assert not service.tasks[("owner", "run")].done()
    await asyncio.wait_for(stream.aclose(), 1)
    assert not service.tasks


@pytest.mark.asyncio
async def test_stopping_audio_keeps_text_running():
    service = ChatSpeechService(None)
    released = asyncio.Event()

    async def events():
        yield {"type": "start"}
        await released.wait()
        yield {"type": "text_delta", "content": "继续回复。"}
        yield {"type": "segment", "content": "继续回复。"}
        yield {"type": "done"}

    async def synthesize(*args):
        await asyncio.Event().wait()

    service._synthesize = synthesize
    stream = service.events(SimpleNamespace(events=events), "owner", "run", "voice")
    await anext(stream)
    await service.stop("owner", "run")
    released.set()
    assert [event["type"] async for event in stream] == ["segment", "done"]
    assert not service.tasks
