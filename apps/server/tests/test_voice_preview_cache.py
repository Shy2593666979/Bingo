import asyncio

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
        b"wav", b"wav"
    ]
    assert await service.preview("voice") == b"wav"
    assert calls == ["voice"]


@pytest.mark.asyncio
async def test_preview_failure_can_retry_and_expired_cache_regenerates(monkeypatch):
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
    service.preview_cache["voice"] = (0, b"old")
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
