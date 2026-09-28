import asyncio
import json
import logging
import time
import uuid
from contextlib import suppress
from typing import Any

from fastapi import WebSocket, WebSocketDisconnect
from websockets.asyncio.client import ClientConnection, connect
from websockets.exceptions import ConnectionClosed

from bingo.services.logging import log_event

logger = logging.getLogger(__name__)


class UpstreamAsrError(Exception):
    pass


class RealtimeAsrProxy:
    """Proxy raw PCM to DashScope's duplex recognition WebSocket protocol."""

    def __init__(
        self,
        *,
        api_key: str,
        url: str,
        model: str,
        audio_format: str,
        sample_rate: int,
        timeout_seconds: float,
    ) -> None:
        self._api_key = api_key
        self._url = url
        self._model = model
        self._audio_format = audio_format
        self._sample_rate = sample_rate
        self._timeout_seconds = timeout_seconds

    async def run(self, client: WebSocket, *, user_id: str | None = None) -> None:
        task_id = uuid.uuid4().hex
        started_at = time.perf_counter()
        try:
            async with connect(
                self._url,
                additional_headers={"Authorization": f"Bearer {self._api_key}"},
                open_timeout=self._timeout_seconds,
                close_timeout=2,
                max_size=4 * 1024 * 1024,
                proxy=None,
            ) as upstream:
                await upstream.send(
                    json.dumps(
                        _run_task(
                            task_id,
                            self._model,
                            audio_format=self._audio_format,
                            sample_rate=self._sample_rate,
                        )
                    )
                )
                await self._wait_until_started(upstream, task_id)
                log_event(logger, logging.INFO, "asr.connected", user_id=user_id)
                await client.send_json({"type": "ready"})

                sender = asyncio.create_task(self._send_audio(client, upstream, task_id))
                receiver = asyncio.create_task(self._receive_results(client, upstream, task_id))
                done, _ = await asyncio.wait(
                    {sender, receiver}, return_when=asyncio.FIRST_COMPLETED
                )

                if receiver in done:
                    sender.cancel()
                    with suppress(asyncio.CancelledError):
                        await sender
                    receiver.result()
                    log_event(
                        logger,
                        logging.INFO,
                        "asr.completed",
                        user_id=user_id,
                        duration_ms=_duration_ms(started_at),
                        outcome="finished",
                    )
                    return

                command = sender.result()
                if command == "finish":
                    await asyncio.wait_for(receiver, timeout=self._timeout_seconds)
                else:
                    receiver.cancel()
                    with suppress(asyncio.CancelledError):
                        await receiver
                log_event(
                    logger,
                    logging.INFO,
                    "asr.completed",
                    user_id=user_id,
                    duration_ms=_duration_ms(started_at),
                    outcome=command,
                )
        except WebSocketDisconnect:
            log_event(
                logger,
                logging.INFO,
                "asr.completed",
                user_id=user_id,
                duration_ms=_duration_ms(started_at),
                outcome="disconnected",
            )
            return
        except (ConnectionClosed, OSError, TimeoutError, ValueError, UpstreamAsrError) as error:
            log_event(
                logger,
                logging.ERROR,
                "asr.failed",
                user_id=user_id,
                duration_ms=_duration_ms(started_at),
                error_type=type(error).__name__,
            )
            await _send_error(client, f"实时语音识别失败：{error}")

    async def _wait_until_started(
        self,
        upstream: ClientConnection,
        task_id: str,
    ) -> None:
        raw_event = await asyncio.wait_for(upstream.recv(), timeout=self._timeout_seconds)
        event = _json_event(raw_event)
        _validate_task(event, task_id)
        event_type = event.get("header", {}).get("event")
        if event_type == "task-failed":
            raise UpstreamAsrError(_failure_message(event))
        if event_type != "task-started":
            raise UpstreamAsrError(f"预期 task-started，实际收到 {event_type}")

    async def _send_audio(
        self,
        client: WebSocket,
        upstream: ClientConnection,
        task_id: str,
    ) -> str:
        while True:
            message = await client.receive()
            if message["type"] == "websocket.disconnect":
                raise WebSocketDisconnect(message.get("code", 1000))
            audio = message.get("bytes")
            if audio:
                await upstream.send(audio)
                continue
            command = _parse_command(message.get("text"))
            if command == "finish":
                await upstream.send(json.dumps(_finish_task(task_id)))
                return "finish"
            if command == "cancel":
                return "cancel"

    async def _receive_results(
        self,
        client: WebSocket,
        upstream: ClientConnection,
        task_id: str,
    ) -> None:
        sentences: list[str] = []
        latest_partial = ""
        async for raw_event in upstream:
            if isinstance(raw_event, bytes):
                continue
            event = _json_event(raw_event)
            _validate_task(event, task_id)
            event_type = event.get("header", {}).get("event")
            if event_type == "task-failed":
                raise UpstreamAsrError(_failure_message(event))
            if event_type == "result-generated":
                sentence = event.get("payload", {}).get("output", {}).get("sentence") or {}
                text = str(sentence.get("text", "")).strip()
                if sentence.get("end_time") is not None:
                    if text:
                        sentences.append(text)
                    latest_partial = ""
                else:
                    latest_partial = text
                await client.send_json(
                    {"type": "partial", "text": "".join(sentences) + latest_partial}
                )
            elif event_type == "task-finished":
                transcript = "".join(sentences) or latest_partial
                await client.send_json({"type": "completed", "text": transcript})
                return


def _run_task(
    task_id: str,
    model: str,
    *,
    audio_format: str = "pcm",
    sample_rate: int = 16000,
) -> dict[str, Any]:
    return {
        "header": {"action": "run-task", "task_id": task_id, "streaming": "duplex"},
        "payload": {
            "model": model,
            "task_group": "audio",
            "task": "recognition",
            "function": "recognition",
            "input": {},
            "parameters": {"format": audio_format, "sample_rate": sample_rate},
        },
    }


def _finish_task(task_id: str) -> dict[str, Any]:
    return {
        "header": {"action": "finish-task", "task_id": task_id, "streaming": "duplex"},
        "payload": {"input": {}},
    }


def _json_event(raw: str | bytes) -> dict[str, Any]:
    if isinstance(raw, bytes):
        raise UpstreamAsrError("上游返回了非预期的二进制消息")
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise UpstreamAsrError("上游返回格式无效")
    return value


def _validate_task(event: dict[str, Any], task_id: str) -> None:
    received = event.get("header", {}).get("task_id")
    if received and received != task_id:
        raise UpstreamAsrError("上游任务 ID 不匹配")


def _failure_message(event: dict[str, Any]) -> str:
    header = event.get("header", {})
    return str(header.get("error_message") or header.get("error_code") or "上游任务失败")


def _parse_command(raw: str | None) -> str:
    if not raw:
        return ""
    value: Any = json.loads(raw)
    return str(value.get("type", "")) if isinstance(value, dict) else ""


async def _send_error(client: WebSocket, message: str) -> None:
    with suppress(RuntimeError, WebSocketDisconnect):
        await client.send_json({"type": "error", "message": message})


def _duration_ms(started_at: float) -> int:
    return round((time.perf_counter() - started_at) * 1000)
