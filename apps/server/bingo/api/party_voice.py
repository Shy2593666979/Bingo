"""Game voice adapter reusing the existing ASR proxy, TTS and native played protocol."""

import asyncio
import difflib
import json
import time
from contextlib import aclosing, suppress
from uuid import uuid4

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from bingo.api.party_games import GameAction
from bingo.services import auth, party_rules
from bingo.services.asr import RealtimeAsrProxy
from bingo.services.exceptions import ServiceError
from bingo.services.group_call_barge_in import BargeInEvidence

router = APIRouter(tags=["party-voice"])


def playback_echo(text, spoken, playing):
    # Short answers such as “真心话” remain valid even when they repeat a prompt.
    return bool(
        playing
        and spoken
        and len(text) >= 6
        and (text in spoken or difflib.SequenceMatcher(None, text, spoken).ratio() > 0.85)
    )


@router.websocket("/games/{identifier}/voice")
async def game_voice(socket: WebSocket, identifier: str):
    scheme, _, token = socket.headers.get("authorization", "").partition(" ")
    app = socket.app.state
    user = (
        await auth.authenticated_user(app.database, token) if scheme.lower() == "bearer" else None
    )
    if not user:
        await socket.close(code=4401, reason="请先登录")
        return
    service, settings = app.party_games, app.settings
    if not settings.asr.api_key or not settings.realtime_call.api_key:
        await socket.close(code=1013, reason="语音服务尚未配置")
        return
    try:
        await service.get(identifier, user.id)
    except ServiceError:
        await socket.close(code=4404, reason="小聚不存在")
        return
    await socket.accept()
    lock, evidence = asyncio.Lock(), BargeInEvidence(settings.asr.realtime.sample_rate)
    stopped = False
    spoken = ""
    hypothesis_at = 0.0
    suspended = False
    connected = False
    audio_task = None
    audio_epoch = None
    published_epoch = -1
    last_voice_evidence = float("-inf")

    async def emit(event):
        async with lock:
            await socket.send_json(event)

    async def action(kind, value="", epoch=0):
        snapshot = await service.get(identifier, user.id)
        return await service.action(
            identifier,
            user.id,
            GameAction(
                type=kind,
                value=value,
                command_id=str(uuid4()),
                revision=snapshot["revision"],
                epoch=epoch,
            ),
        )

    async def watch_updates():
        nonlocal suspended, published_epoch
        sent_revision = -1
        while not stopped:
            if not connected:
                await asyncio.sleep(0.1)
                continue
            snapshot = await service.get(identifier, user.id)
            if snapshot["revision"] != sent_revision:
                await emit({"type": "game_state", "state": snapshot})
                sent_revision = snapshot["revision"]
            epoch = snapshot["voice_epoch"]
            if epoch != published_epoch:
                await emit({"type": "interrupted", "generation": epoch})
                published_epoch = epoch
                if audio_task is not None and audio_epoch != epoch:
                    audio_task.cancel()
            if snapshot["phase"] == "finished":
                await emit({"type": "ended"})
                return
            if suspended and time.monotonic() - hypothesis_at > 2 and not evidence.recent_voice():
                await action("recover")
                suspended = False
            await asyncio.sleep(0.1)

    async def synthesize(snapshot, item):
        nonlocal spoken
        epoch, pending = snapshot["voice_epoch"], snapshot["playback"]
        role = await service.role(user.id, item["speaker"])
        if (await service.get(identifier, user.id))["voice_epoch"] != epoch:
            return
        spoken = item["text"]
        await emit(
            {
                "type": "speaker",
                "role_id": role.id,
                "text": spoken,
                "generation": epoch,
                "utterance_id": pending,
            }
        )
        async with aclosing(
            app.services.chat_speech.message_events(
                spoken, role.voice or settings.realtime_call.voice
            )
        ) as stream:
            async for event in stream:
                current = await service.get(identifier, user.id)
                if current["voice_epoch"] != epoch:
                    return
                if event["type"] == "audio_error":
                    await action("pause")
                    await emit(
                        {
                            "type": "participant_error",
                            "message": "朗读失败，游戏已暂停，可返回文字继续",
                        }
                    )
                    return
                if event["type"] == "audio":
                    await emit({**event, "generation": epoch})
                if event["type"] == "audio_done":
                    await emit({"type": "audio_end", "generation": epoch, "utterance_id": pending})

    async def audio_loop():
        nonlocal audio_task, audio_epoch
        handled, sent_wait = None, None
        while not stopped:
            if not connected:
                await asyncio.sleep(0.1)
                continue
            snapshot = await service.get(identifier, user.id)
            epoch = snapshot["voice_epoch"]
            if published_epoch != epoch:
                await asyncio.sleep(0.05)
                continue
            pending = snapshot["playback"]
            if pending and pending != handled:
                handled = pending
                item = next((m for m in snapshot["messages"] if m["id"] == pending), None)
                if not item:
                    raise ValueError("Invalid game playback")
                audio_epoch = epoch
                audio_task = asyncio.create_task(synthesize(snapshot, item))
                try:
                    await audio_task
                except asyncio.CancelledError:
                    if asyncio.current_task().cancelling():
                        raise
                finally:
                    audio_task = None
                deadline = time.monotonic() + 90
                while time.monotonic() < deadline and not stopped:
                    current = await service.get(identifier, user.id)
                    if current["playback"] != pending or current["voice_epoch"] != epoch:
                        break
                    await asyncio.sleep(0.15)
                else:
                    if not stopped:
                        await action("pause")
                        await emit(
                            {"type": "participant_error", "message": "未确认播放完成，游戏已暂停"}
                        )
                if (await service.get(identifier, user.id))["voice_epoch"] != epoch:
                    continue
            wait = (snapshot["phase"], snapshot["round"], json.dumps(snapshot["options"]))
            if wait != sent_wait and (snapshot["options"] or snapshot["can_speak"]):
                sent_wait = wait
                hint = (snapshot["action_hint"] or "") + "；".join(snapshot["options"].values())
                await emit(
                    {"type": "command_error", "message": (hint or "轮到你发言，可以直接说话")[:300]}
                )
            await asyncio.sleep(0.15)

    class Bridge:
        async def receive(self):
            nonlocal stopped, connected, last_voice_evidence
            while True:
                event = await socket.receive()
                if event["type"] == "websocket.disconnect":
                    raise WebSocketDisconnect()
                if event.get("bytes"):
                    if len(event["bytes"]) > 65536:
                        raise ValueError("Audio frame too large")
                    evidence.observe(event["bytes"])
                    if evidence.supports_speech(final=True):
                        last_voice_evidence = time.monotonic()
                    return event
                try:
                    command = json.loads(event.get("text") or "{}")
                except ValueError:
                    continue
                if not isinstance(command, dict):
                    continue
                kind = command.get("type")
                if kind == "hangup":
                    stopped = True
                    return {"type": "websocket.receive", "text": '{"type":"cancel"}'}
                if kind == "client_audio_ready" and not connected:
                    await action("voice_start")
                    connected = True
                elif kind == "played":
                    current = await service.get(identifier, user.id)
                    if (
                        command.get("generation") != current["voice_epoch"]
                        or command.get("utterance_id") != current["playback"]
                    ):
                        continue
                    if command.get("status") == "completed":
                        with suppress(ServiceError):
                            await action(
                                "played",
                                command.get("utterance_id", ""),
                                command.get("generation", -1),
                            )
                    else:
                        await action("pause")
                elif kind in {"game_choice", "game_action"}:
                    requested = "choice" if kind == "game_choice" else command.get("action")
                    if requested not in {"choice", "pause", "resume", "advance"}:
                        continue
                    try:
                        await service.action(
                            identifier,
                            user.id,
                            GameAction(
                                type=requested,
                                value=command.get("value", ""),
                                revision=command.get("revision", 0),
                                stage=command.get("stage", ""),
                                command_id=str(uuid4()),
                            ),
                        )
                    except (ServiceError, ValueError) as error:
                        await emit({"type": "command_error", "message": str(error)})

        async def send_json(self, event):
            nonlocal hypothesis_at, suspended, last_voice_evidence
            kind, text = event.get("type"), event.get("text", "").strip()
            if kind == "ready":
                await emit({"type": "ready"})
            elif kind in {"speech_partial", "sentence"}:
                credible = evidence.supports_speech(final=kind == "sentence")
                # A final ASR sentence may arrive after VAD silence pruned the PCM window.
                credible = credible or (
                    kind == "sentence" and time.monotonic() - last_voice_evidence <= 3
                )
                if not text or not credible:
                    return
                current = await service.get(identifier, user.id)
                if playback_echo(text, spoken, current["playback"]):
                    return
                if kind == "speech_partial":
                    if len(text) >= 3:
                        hypothesis_at = time.monotonic()
                        if not suspended:
                            changed = await action("interrupt")
                            await emit(
                                {"type": "interrupted", "generation": changed["voice_epoch"]}
                            )
                            suspended = True
                    return
                await emit({"type": "user_transcript", "text": text})
                try:
                    snapshot = await service.get(identifier, user.id)
                    choices = snapshot["options"]
                    state, _ = await service.load(identifier, user.id)
                    state = {
                        **state,
                        "messages": [
                            *state["messages"],
                            {
                                "id": "voice-input",
                                "speaker": party_rules.SELF,
                                "text": text,
                                "round": state["round"],
                                "recipients": [party_rules.SELF],
                            },
                        ],
                    }
                    candidates = {f"option:{k}": v for k, v in choices.items()}
                    candidates.update(
                        pause="明确要求暂停",
                        resume="明确要求继续",
                        end="明确要求结束本局",
                        clarify="没有明确合法操作",
                    )
                    if snapshot["can_advance"]:
                        candidates["advance"] = "明确跳过本轮或进入投票"
                    if (
                        snapshot["mode"] == "truth"
                        and snapshot["actor"] == "self"
                        and snapshot["phase"] == "answer"
                    ):
                        candidates["change_question"] = "明确要求换一道题"
                    if (
                        snapshot["can_speak"]
                        or snapshot["mode"] == "truth"
                        or (snapshot["phase"] == "speech" and "self" in snapshot["alive"])
                    ):
                        candidates["say"] = "普通发言、回答、表达观点或插话，不是控制命令"
                    chosen = await service.ai.choose(
                        state,
                        party_rules.SELF,
                        candidates,
                        "只判断用户最后一句明确选择了哪个操作，不替用户猜测或做策略决定。",
                    )
                    if chosen == "clarify":
                        await action("recover")
                        await emit({"type": "command_error", "message": "请明确说出你的选择"})
                    elif chosen.startswith("option:"):
                        await action("choice", chosen.removeprefix("option:"))
                    else:
                        await action(chosen, text if chosen == "say" else "")
                except ServiceError as error:
                    await action("recover")
                    await emit({"type": "command_error", "message": str(error)})
                except asyncio.CancelledError:
                    raise
                except Exception:
                    await action("pause")
                    await emit(
                        {
                            "type": "participant_error",
                            "message": "语音操作识别失败，游戏已暂停，可重试或点选操作",
                        }
                    )
                suspended = False
                evidence.reset()
                last_voice_evidence = float("-inf")
            elif kind == "error":
                await emit(event)

    task = asyncio.create_task(audio_loop())
    updates_task = asyncio.create_task(watch_updates())
    cfg = settings.asr.realtime
    proxy_task = asyncio.create_task(
        RealtimeAsrProxy(
            api_key=settings.asr.api_key,
            url=cfg.url,
            model=cfg.model,
            audio_format=cfg.format,
            sample_rate=cfg.sample_rate,
            timeout_seconds=cfg.timeout_seconds,
            sentence_events=True,
        ).run(Bridge(), user_id=user.id)
    )
    try:
        done, _ = await asyncio.wait(
            [task, updates_task, proxy_task], return_when=asyncio.FIRST_COMPLETED
        )
        for result in done:
            result.result()
    except (WebSocketDisconnect, RuntimeError, ValueError):
        pass
    finally:
        stopped = True
        task.cancel()
        updates_task.cancel()
        proxy_task.cancel()
        await asyncio.gather(task, updates_task, proxy_task, return_exceptions=True)
        if connected:
            with suppress(ServiceError):
                await action("voice_stop")
        with suppress(RuntimeError):
            await socket.close()
