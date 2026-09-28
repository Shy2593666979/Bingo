import base64
import logging
import time

import httpx
from fastapi import APIRouter, HTTPException, Request, WebSocket, status

from bingo.api.dependencies import CurrentUserDependency
from bingo.db.repositories import AuthSessionRepository
from bingo.services.asr import RealtimeAsrProxy
from bingo.services.logging import log_event

router = APIRouter(tags=["asr"])
logger = logging.getLogger(__name__)

MAX_AUDIO_BYTES = 10 * 1024 * 1024
MIN_WAV_BYTES = 44


@router.websocket("/asr/realtime")
async def realtime_transcribe(websocket: WebSocket) -> None:
    authorization = websocket.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        await websocket.close(code=4401, reason="请先登录")
        return

    async with websocket.app.state.database.session_factory() as session:
        user = await AuthSessionRepository(session).get_user(token)
    if user is None:
        await websocket.close(code=4401, reason="登录已失效")
        return

    settings = websocket.app.state.settings
    if not settings.asr.api_key:
        await websocket.close(code=1013, reason="后台未配置 DashScope API Key")
        return

    await websocket.accept()
    proxy = RealtimeAsrProxy(
        api_key=settings.asr.api_key,
        url=settings.asr.realtime.url,
        model=settings.asr.realtime.model,
        audio_format=settings.asr.realtime.format,
        sample_rate=settings.asr.realtime.sample_rate,
        timeout_seconds=settings.asr.realtime.timeout_seconds,
    )
    await proxy.run(websocket, user_id=user.id)


@router.post("/asr/transcribe")
async def transcribe_audio(
    request: Request,
    user: CurrentUserDependency,
) -> dict[str, str]:
    started_at = time.perf_counter()
    settings = request.app.state.settings
    if not settings.asr.api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="后台未配置 DashScope 语音识别 API Key",
        )

    audio = await request.body()
    if len(audio) < MIN_WAV_BYTES:
        raise HTTPException(status_code=422, detail="录音内容为空")
    if len(audio) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="录音过长，请缩短后重试")
    if request.headers.get("content-type", "").split(";", 1)[0] != "audio/wav":
        raise HTTPException(status_code=415, detail="仅支持 WAV 录音")

    data_url = "data:audio/wav;base64," + base64.b64encode(audio).decode("ascii")
    payload = {
        "model": settings.asr.file.model,
        "input": {
            "messages": [
                {
                    "role": "user",
                    "content": [{"audio": data_url}],
                }
            ]
        },
        "parameters": {
            "asr_options": {
                "language": settings.asr.file.language,
                "enable_itn": True,
            }
        },
    }
    try:
        async with httpx.AsyncClient(timeout=settings.asr.file.timeout_seconds) as client:
            response = await client.post(
                settings.asr.file.base_url,
                headers={
                    "Authorization": f"Bearer {settings.asr.api_key}",
                    "X-DashScope-SSE": "disable",
                },
                json=payload,
            )
        response.raise_for_status()
        result = response.json()
        text = str(result["output"]["choices"][0]["message"]["content"][0]["text"]).strip()
    except httpx.HTTPStatusError as error:
        _log_file_asr_failure(user.id, started_at, len(audio), error)
        detail = _upstream_error(error.response)
        raise HTTPException(status_code=502, detail=f"语音识别失败：{detail}") from error
    except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError) as error:
        _log_file_asr_failure(user.id, started_at, len(audio), error)
        raise HTTPException(status_code=502, detail="语音识别服务暂时不可用") from error

    if not text:
        _log_file_asr_failure(user.id, started_at, len(audio), ValueError())
        raise HTTPException(status_code=422, detail="没有识别到清晰的语音")
    log_event(
        logger,
        logging.INFO,
        "asr.completed",
        user_id=user.id,
        audio_bytes=len(audio),
        duration_ms=round((time.perf_counter() - started_at) * 1000),
        outcome="file",
    )
    return {"text": text}


def _upstream_error(response: httpx.Response) -> str:
    try:
        payload = response.json()
        return str(
            payload.get("error", {}).get("message") or payload.get("message") or "上游服务错误"
        )
    except ValueError:
        return "上游服务错误"


def _log_file_asr_failure(
    user_id: str,
    started_at: float,
    audio_bytes: int,
    error: Exception,
) -> None:
    log_event(
        logger,
        logging.ERROR,
        "asr.failed",
        user_id=user_id,
        audio_bytes=audio_bytes,
        duration_ms=round((time.perf_counter() - started_at) * 1000),
        error_type=type(error).__name__,
    )
