import asyncio
import base64
import json
from typing import Any

import pytest

from bingo.services.realtime_call import RealtimeCallProxy, derive_realtime_url


class _Client:
    def __init__(self) -> None:
        self.json_events: list[dict[str, Any]] = []
        self.audio: list[bytes] = []

    async def send_json(self, event: dict[str, Any]) -> None:
        self.json_events.append(event)

    async def send_bytes(self, audio: bytes) -> None:
        self.audio.append(audio)


class _Upstream:
    def __init__(self, events: list[dict[str, Any]]) -> None:
        self._events = iter(events)
        self.sent: list[dict[str, Any]] = []

    async def send(self, value: str) -> None:
        self.sent.append(json.loads(value))

    def __aiter__(self) -> "_Upstream":
        return self

    async def __anext__(self) -> str:
        try:
            return json.dumps(next(self._events))
        except StopIteration as error:
            raise StopAsyncIteration from error


def _proxy(*, start_with_response: bool = False) -> RealtimeCallProxy:
    return RealtimeCallProxy(
        api_key="key",
        url="wss://workspace.example/api-ws/v1/realtime",
        model="qwen-audio-3.1-realtime-plus",
        voice="voice",
        instructions="instructions",
        history=[],
        tools=[],
        turn_detection="smart_turn",
        max_history_turns=20,
        timeout_seconds=10,
        start_with_response=start_with_response,
    )


def test_derive_realtime_url_reuses_workspace_host() -> None:
    assert (
        derive_realtime_url("", "wss://workspace.example/api-ws/v1/inference")
        == "wss://workspace.example/api-ws/v1/realtime"
    )


@pytest.mark.asyncio
async def test_receive_events_decodes_audio_and_persists_transcripts() -> None:
    audio = b"\x01\x02\x03"
    events = [
        {"type": "response.audio.delta", "delta": base64.b64encode(audio).decode()},
        {
            "type": "conversation.item.input_audio_transcription.completed",
            "transcript": "你好",
        },
        {"type": "response.audio_transcript.done", "transcript": "你好呀"},
    ]
    client = _Client()
    transcripts: list[tuple[str, str]] = []

    async def persist(role: str, text: str) -> None:
        transcripts.append((role, text))

    async def execute_tool(name: str, arguments: str) -> tuple[str, None]:
        return "", None

    await _proxy()._receive_events(  # noqa: SLF001
        client,  # type: ignore[arg-type]
        _Upstream(events),  # type: ignore[arg-type]
        persist,
        execute_tool,
    )

    assert client.audio == [audio]
    assert transcripts == [("user", "你好"), ("assistant", "你好呀")]
    assert client.json_events[-1] == {
        "type": "assistant_transcript.done",
        "text": "你好呀",
    }


@pytest.mark.asyncio
async def test_initial_response_waits_for_client_audio_and_starts_once() -> None:
    proxy = _proxy(start_with_response=True)
    upstream = _Upstream([])
    started = asyncio.Event()

    await proxy._configure(upstream)  # noqa: SLF001
    assert all(event["type"] != "response.create" for event in upstream.sent)

    await proxy._start_initial_response(upstream, started)  # noqa: SLF001
    await proxy._start_initial_response(upstream, started)  # noqa: SLF001
    assert [event["type"] for event in upstream.sent].count("response.create") == 1
