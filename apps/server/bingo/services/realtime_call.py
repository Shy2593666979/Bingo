import asyncio
import base64
import json
import logging
import time
from collections.abc import Awaitable, Callable
from contextlib import suppress
from dataclasses import dataclass
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from fastapi import WebSocket, WebSocketDisconnect
from websockets.asyncio.client import ClientConnection, connect
from websockets.exceptions import ConnectionClosed

from bingo.services.logging import log_event

logger = logging.getLogger(__name__)

TranscriptHandler = Callable[[str, str], Awaitable[None]]
ToolHandler = Callable[[str, str], Awaitable[tuple[str, dict[str, Any] | None]]]
CallFinishedHandler = Callable[[str, int], Awaitable[None]]


@dataclass(frozen=True)
class RealtimeCallResult:
    status: str
    duration_seconds: int


class UpstreamRealtimeCallError(Exception):
    pass


class RealtimeCallProxy:
    """Bridge native PCM frames to Qwen-Audio's Realtime event protocol."""

    def __init__(
        self,
        *,
        api_key: str,
        url: str,
        model: str,
        voice: str,
        instructions: str,
        history: list[tuple[str, str]],
        tools: list[dict[str, Any]],
        turn_detection: str,
        max_history_turns: int,
        timeout_seconds: float,
        start_with_response: bool = False,
    ) -> None:
        self._api_key = api_key
        self._url = _model_url(url, model)
        self._voice = voice
        self._instructions = instructions
        self._history = history[-(max_history_turns * 2) :]
        self._tools = tools
        self._turn_detection = turn_detection
        self._max_history_turns = max_history_turns
        self._timeout_seconds = timeout_seconds
        self._start_with_response = start_with_response

    async def run(
        self,
        client: WebSocket,
        *,
        user_id: str,
        conversation_id: str,
        on_transcript: TranscriptHandler,
        on_tool_call: ToolHandler,
        on_finished: CallFinishedHandler | None = None,
    ) -> RealtimeCallResult:
        started_at = time.perf_counter()
        connected_at: float | None = None
        status = "ended"
        try:
            async with connect(
                self._url,
                additional_headers={"Authorization": f"Bearer {self._api_key}"},
                open_timeout=self._timeout_seconds,
                close_timeout=2,
                max_size=8 * 1024 * 1024,
                proxy=None,
            ) as upstream:
                await self._configure(upstream)
                connected_at = time.perf_counter()
                await client.send_json({"type": "ready", "conversation_id": conversation_id})
                log_event(
                    logger,
                    logging.INFO,
                    "realtime_call.connected",
                    user_id=user_id,
                    conversation_id=conversation_id,
                )
                initial_response_started = asyncio.Event()
                sender = asyncio.create_task(
                    self._send_audio(client, upstream, initial_response_started)
                )
                receiver = asyncio.create_task(
                    self._receive_events(client, upstream, on_transcript, on_tool_call)
                )
                fallback = (
                    asyncio.create_task(
                        self._fallback_initial_response(
                            upstream,
                            initial_response_started,
                        )
                    )
                    if self._start_with_response
                    else None
                )
                try:
                    done, pending = await asyncio.wait(
                        {sender, receiver}, return_when=asyncio.FIRST_COMPLETED
                    )
                    for task in pending:
                        task.cancel()
                    for task in pending:
                        with suppress(asyncio.CancelledError):
                            await task
                    for task in done:
                        task.result()
                finally:
                    if fallback is not None:
                        fallback.cancel()
                        with suppress(asyncio.CancelledError):
                            await fallback
        except WebSocketDisconnect:
            pass
        except (
            ConnectionClosed,
            OSError,
            TimeoutError,
            ValueError,
            UpstreamRealtimeCallError,
        ) as error:
            status = "failed"
            log_event(
                logger,
                logging.ERROR,
                "realtime_call.failed",
                user_id=user_id,
                conversation_id=conversation_id,
                duration_ms=_duration_ms(started_at),
                error_type=type(error).__name__,
            )
            await _send_json(client, {"type": "error", "message": f"实时通话失败：{error}"})
        finally:
            duration_seconds = _duration_seconds(connected_at)
            if on_finished is not None:
                await on_finished(status, duration_seconds)
            await _send_json(
                client,
                {
                    "type": "ended",
                    "status": status,
                    "duration_seconds": duration_seconds,
                },
            )
            log_event(
                logger,
                logging.INFO,
                "realtime_call.completed",
                user_id=user_id,
                conversation_id=conversation_id,
                duration_ms=_duration_ms(started_at),
            )
        return RealtimeCallResult(status=status, duration_seconds=duration_seconds)

    async def _configure(self, upstream: ClientConnection) -> None:
        await upstream.send(
            json.dumps(
                {
                    "type": "session.update",
                    "session": {
                        "modalities": ["audio", "text"],
                        "voice": self._voice,
                        "instructions": self._instructions,
                        "input_audio_format": "pcm",
                        "output_audio_format": "pcm",
                        "turn_detection": {"type": self._turn_detection},
                        "max_history_turns": self._max_history_turns,
                        "input_audio_transcription": {"language": "zh"},
                        "output_audio": {"language": "zh"},
                        "tools": self._tools,
                    },
                },
                ensure_ascii=False,
            )
        )
        for role, content in self._history:
            content_type = "output_text" if role == "assistant" else "input_text"
            await upstream.send(
                json.dumps(
                    {
                        "type": "conversation.item.create",
                        "item": {
                            "type": "message",
                            "role": role,
                            "content": [{"type": content_type, "text": content}],
                        },
                    },
                    ensure_ascii=False,
                )
            )

    async def _send_audio(
        self,
        client: WebSocket,
        upstream: ClientConnection,
        initial_response_started: asyncio.Event,
    ) -> None:
        while True:
            message = await client.receive()
            if message["type"] == "websocket.disconnect":
                raise WebSocketDisconnect(message.get("code", 1000))
            audio = message.get("bytes")
            if audio:
                await upstream.send(
                    json.dumps(
                        {
                            "type": "input_audio_buffer.append",
                            "audio": base64.b64encode(audio).decode("ascii"),
                        }
                    )
                )
                continue
            command = _json_event(message.get("text"))
            if command.get("type") == "client_audio_ready":
                if self._start_with_response:
                    await self._start_initial_response(
                        upstream,
                        initial_response_started,
                    )
                continue
            if command.get("type") == "hangup":
                return
            if command.get("type") == "cancel_response":
                await upstream.send(json.dumps({"type": "response.cancel"}))

    async def _fallback_initial_response(
        self,
        upstream: ClientConnection,
        initial_response_started: asyncio.Event,
    ) -> None:
        # Older clients do not send client_audio_ready. Keep them functional,
        # while giving current clients enough time to initialize AudioTrack.
        await asyncio.sleep(2)
        await self._start_initial_response(upstream, initial_response_started)

    async def _start_initial_response(
        self,
        upstream: ClientConnection,
        initial_response_started: asyncio.Event,
    ) -> None:
        if initial_response_started.is_set():
            return
        initial_response_started.set()
        await upstream.send(json.dumps({"type": "response.create"}))

    async def _receive_events(
        self,
        client: WebSocket,
        upstream: ClientConnection,
        on_transcript: TranscriptHandler,
        on_tool_call: ToolHandler,
    ) -> None:
        async for raw in upstream:
            event = _json_event(raw)
            event_type = str(event.get("type", ""))
            if event_type == "error":
                error = event.get("error") or {}
                raise UpstreamRealtimeCallError(str(error.get("message") or "上游服务错误"))
            if event_type == "response.audio.delta":
                audio = base64.b64decode(str(event.get("delta", "")), validate=True)
                if audio:
                    await client.send_bytes(audio)
            elif event_type == "conversation.item.input_audio_transcription.delta":
                await _send_json(
                    client,
                    {
                        "type": "user_transcript.delta",
                        "text": str(event.get("text", "")),
                        "stash": str(event.get("stash", "")),
                    },
                )
            elif event_type == "conversation.item.input_audio_transcription.completed":
                text = str(event.get("transcript", "")).strip()
                if text:
                    await on_transcript("user", text)
                    await _send_json(client, {"type": "user_transcript.done", "text": text})
            elif event_type == "response.audio_transcript.delta":
                await _send_json(
                    client,
                    {"type": "assistant_transcript.delta", "text": str(event.get("delta", ""))},
                )
            elif event_type == "response.audio_transcript.done":
                text = str(event.get("transcript", "")).strip()
                if text:
                    await on_transcript("assistant", text)
                    await _send_json(client, {"type": "assistant_transcript.done", "text": text})
            elif event_type == "input_audio_buffer.speech_started":
                await _send_json(client, {"type": "speech_started"})
            elif event_type == "input_audio_buffer.speech_stopped":
                await _send_json(client, {"type": "speech_stopped"})
            elif event_type == "response.created":
                await _send_json(client, {"type": "assistant_speaking"})
            elif event_type == "response.done":
                response = event.get("response") or {}
                await _send_json(
                    client,
                    {"type": "response_done", "status": str(response.get("status", ""))},
                )
            elif event_type == "response.function_call_arguments.done":
                call_id = str(event.get("call_id", ""))
                name = str(event.get("name", ""))
                arguments = str(event.get("arguments", "{}"))
                output, client_event = await on_tool_call(name, arguments)
                if client_event:
                    await _send_json(client, {"type": "tool_event", "event": client_event})
                await upstream.send(
                    json.dumps(
                        {
                            "type": "conversation.item.create",
                            "item": {
                                "type": "function_call_output",
                                "call_id": call_id,
                                "output": output,
                            },
                        },
                        ensure_ascii=False,
                    )
                )
                await upstream.send(json.dumps({"type": "response.create"}))


def derive_realtime_url(configured: str, asr_url: str) -> str:
    if configured.strip():
        return configured.strip()
    parts = urlsplit(asr_url)
    path = parts.path.replace("/inference", "/realtime")
    return urlunsplit((parts.scheme, parts.netloc, path, "", ""))


def _model_url(url: str, model: str) -> str:
    parts = urlsplit(url)
    query = dict(parse_qsl(parts.query, keep_blank_values=True))
    query["model"] = model
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), parts.fragment))


def _json_event(raw: str | bytes | None) -> dict[str, Any]:
    if raw is None or isinstance(raw, bytes):
        return {}
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("事件格式无效")
    return value


async def _send_json(client: WebSocket, event: dict[str, Any]) -> None:
    with suppress(RuntimeError, WebSocketDisconnect):
        await client.send_json(event)


def _duration_ms(started_at: float) -> int:
    return round((time.perf_counter() - started_at) * 1000)


def _duration_seconds(started_at: float | None) -> int:
    if started_at is None:
        return 0
    return max(0, int(time.perf_counter() - started_at))
