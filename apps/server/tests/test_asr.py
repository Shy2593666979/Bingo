from typing import Any

import pytest

from bingo.services.asr import RealtimeAsrProxy


class _FailingConnection:
    async def __aenter__(self) -> None:
        raise OSError("test connection failure")

    async def __aexit__(self, *args: object) -> None:
        return None


class _Client:
    def __init__(self) -> None:
        self.events: list[dict[str, Any]] = []

    async def send_json(self, event: dict[str, Any]) -> None:
        self.events.append(event)


@pytest.mark.asyncio
async def test_realtime_asr_bypasses_environment_proxy(monkeypatch: pytest.MonkeyPatch) -> None:
    options: dict[str, Any] = {}

    def fake_connect(url: str, **kwargs: Any) -> _FailingConnection:
        options.update(kwargs)
        return _FailingConnection()

    monkeypatch.setattr("bingo.services.asr.connect", fake_connect)
    client = _Client()
    proxy = RealtimeAsrProxy(
        api_key="test-key",
        url="wss://example.com/asr",
        model="test-model",
        audio_format="pcm",
        sample_rate=16000,
        timeout_seconds=10,
    )

    await proxy.run(client)  # type: ignore[arg-type]

    assert options["proxy"] is None
    assert client.events[0]["type"] == "error"
