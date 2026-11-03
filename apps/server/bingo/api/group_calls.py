import asyncio
import json
from contextlib import suppress

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field, ValidationError

from bingo.services import auth
from bingo.services.asr import RealtimeAsrProxy
from bingo.services.exceptions import ServiceError
from bingo.services.group_call import GroupCallSession
from bingo.services.group_call_lifecycle import GroupCallLifecycle, participants

router = APIRouter(tags=["group-calls"])


class CallJoin(BaseModel):
    role_ids: list[str] = Field(min_length=1, max_length=8)


@router.websocket("/groups/{group_id}/calls/stream")
async def group_call(socket: WebSocket, group_id: str):
    scheme, _, token = socket.headers.get("authorization", "").partition(" ")
    database, settings = socket.app.state.database, socket.app.state.settings
    user = (
        await auth.authenticated_user(database, token)
        if scheme.lower() == "bearer" and token
        else None
    )
    if not user:
        await socket.close(code=4401, reason="请先登录")
        return
    try:
        join = CallJoin(role_ids=socket.query_params.getlist("role_id"))
        roles, history = await participants(database, user.id, group_id, join.role_ids)
    except (ValidationError, ServiceError):
        await socket.close(code=4409, reason="请从当前群聊选择一至八位搭子")
        return
    if not settings.asr.api_key or not settings.realtime_call.api_key:
        await socket.close(code=1013, reason="后台语音服务尚未配置")
        return
    active = getattr(socket.app.state, "active_group_calls", None)
    if active is None:
        active = socket.app.state.active_group_calls = set()
    if user.id in active:
        await socket.close(code=4409, reason="已有一通群聊电话进行中")
        return
    active.add(user.id)
    status = "failed"
    lock = asyncio.Lock()
    context = socket.app.state.services
    lifecycle = GroupCallLifecycle(database, context.group_chat, group_id, user.id, join.role_ids)

    async def emit(event):
        async with lock:
            await socket.send_json(event)

    engine = GroupCallSession(
        roles=roles,
        model=context.group_chat.model,
        speech=context.chat_speech,
        emit=emit,
        history=history,
        voice_fallback=settings.realtime_call.voice,
    )

    class AsrBridge:
        async def receive(self):
            nonlocal status
            while True:
                message = await socket.receive()
                if message["type"] == "websocket.disconnect":
                    raise WebSocketDisconnect(message.get("code", 1000))
                if message.get("bytes"):
                    if len(message["bytes"]) > 65536:
                        raise ValueError("音频帧过大")
                    return message
                try:
                    command = json.loads(message.get("text") or "{}")
                except ValueError:
                    continue
                kind = command.get("type")
                if kind == "hangup":
                    status = "ended"
                    return {"type": "websocket.receive", "text": '{"type":"cancel"}'}
                if kind == "played":
                    engine.acknowledge(command.get("utterance_id"))
                elif kind == "client_audio_ready" and not engine.started:
                    engine.started = True
                    engine.task = asyncio.create_task(engine.respond("", greeting=True))
                elif kind == "interrupt":
                    await engine.interrupt()

        async def send_json(self, event):
            nonlocal status
            kind = event.get("type")
            if kind == "ready":
                status = "connected"
                await emit({"type": "ready", "call_id": lifecycle.call.id})
            elif kind == "speech_partial":
                await engine.partial(event["text"])
            elif kind == "sentence":
                await engine.sentence(event["text"])
            elif kind == "error":
                status = "failed"
                await emit(event)

    try:
        await lifecycle.prepare(engine)
        await socket.accept()
        cfg = settings.asr.realtime
        proxy = RealtimeAsrProxy(
            api_key=settings.asr.api_key,
            url=cfg.url,
            model=cfg.model,
            audio_format=cfg.format,
            sample_rate=cfg.sample_rate,
            timeout_seconds=cfg.timeout_seconds,
            sentence_events=True,
        )
        await proxy.run(AsrBridge(), user_id=user.id)
    except (WebSocketDisconnect, RuntimeError, ValueError):
        pass
    finally:
        await engine.close()
        active.discard(user.id)
        await lifecycle.finish(status, engine)
        with suppress(Exception):
            await emit({"type": "ended", "call_id": lifecycle.call.id})
            await socket.close()
