import asyncio
from contextlib import aclosing

import pytest

from bingo.config import Settings
from bingo.services.voice_cloning import VoiceCloningService


@pytest.mark.asyncio
async def test_preview_reuses_success_and_coalesces_requests(monkeypatch):
    service = VoiceCloningService(None, Settings())
    calls = []

    async def generate(voice):
        calls.append(voice)
        await asyncio.sleep(0)
        return b"wav"

    monkeypatch.setattr(service, "generate_preview", generate)
    assert await asyncio.gather(service.preview("voice"), service.preview("voice")) == [
        b"wav",
        b"wav",
    ]
    assert await service.preview("voice") == b"wav"
    assert calls == ["voice"]


@pytest.mark.asyncio
@pytest.mark.parametrize("started_at", [0.0, 30.0, 86400.0])
async def test_preview_failure_can_retry_and_expired_cache_regenerates(monkeypatch, started_at):
    now = started_at
    monkeypatch.setattr("bingo.services.voice_cloning.monotonic", lambda: now)
    service = VoiceCloningService(None, Settings())
    calls = []

    async def generate(voice):
        calls.append(voice)
        if len(calls) == 1:
            raise ValueError("failed")
        return b"wav"

    monkeypatch.setattr(service, "generate_preview", generate)
    with pytest.raises(ValueError):
        await service.preview("voice")
    assert await service.preview("voice") == b"wav"
    assert len(calls) == 2
    now = started_at + 599
    assert await service.preview("voice") == b"wav"
    assert len(calls) == 2
    now = started_at + 600
    assert await service.preview("voice") == b"wav"
    assert len(calls) == 3


@pytest.mark.asyncio
async def test_preview_cache_is_bounded(monkeypatch):
    service = VoiceCloningService(None, Settings())

    async def generate(voice):
        return voice.encode()

    monkeypatch.setattr(service, "generate_preview", generate)
    for index in range(20):
        await service.preview(str(index))
    assert len(service.preview_cache) == 16
    assert "0" not in service.preview_cache


@pytest.mark.asyncio
async def test_cancelled_caller_does_not_cancel_shared_generation(monkeypatch):
    service = VoiceCloningService(None, Settings())
    started = asyncio.Event()
    release = asyncio.Event()

    async def generate(voice):
        started.set()
        await release.wait()
        return b"wav"

    monkeypatch.setattr(service, "generate_preview", generate)
    caller = asyncio.create_task(service.preview("voice"))
    await started.wait()
    caller.cancel()
    with pytest.raises(asyncio.CancelledError):
        await caller
    release.set()
    assert await service.preview("voice") == b"wav"
    await service.close()


@pytest.mark.asyncio
async def test_stream_yields_before_generation_finishes_and_reuses_completed_audio(monkeypatch):
    service = VoiceCloningService(None, Settings())
    release = asyncio.Event()
    first, second = b"\x01\x00", b"\x02\x00"

    async def deltas(voice):
        yield first
        await release.wait()
        yield second

    monkeypatch.setattr(service, "preview_deltas", deltas)
    async with aclosing(service.stream_preview("voice")) as stream:
        assert await asyncio.wait_for(anext(stream), 1) == first
        assert service.cached_preview("voice") is None
        release.set()
        assert [chunk async for chunk in stream] == [second]

    assert [chunk async for chunk in service.stream_preview("voice")] == [first + second]
