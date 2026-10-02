import base64
import logging
import time

import httpx

from bingo.db.models import User
from bingo.services.context import ServiceContext
from bingo.services.exceptions import ServiceError
from bingo.services.logging import log_event

logger = logging.getLogger(__name__)
MAX_AUDIO_BYTES = 10 * 1024 * 1024
MIN_WAV_BYTES = 44


async def transcribe_audio(
    context: ServiceContext, user: User, audio: bytes, content_type: str
) -> dict[str, str]:
    started_at = time.perf_counter()
    settings = context.settings
    if not settings.asr.api_key:
        raise ServiceError(status_code=503, detail="后台未配置 DashScope 语音识别 API Key")
    if len(audio) < MIN_WAV_BYTES:
        raise ServiceError(status_code=422, detail="录音内容为空")
    if len(audio) > MAX_AUDIO_BYTES:
        raise ServiceError(status_code=413, detail="录音过长，请缩短后重试")
    if content_type.split(";", 1)[0] != "audio/wav":
        raise ServiceError(status_code=415, detail="仅支持 WAV 录音")
    data_url = "data:audio/wav;base64," + base64.b64encode(audio).decode("ascii")
    payload = {
        "model": settings.asr.file.model,
        "input": {"messages": [{"role": "user", "content": [{"audio": data_url}]}]},
        "parameters": {"asr_options": {"language": settings.asr.file.language, "enable_itn": True}},
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
        raise ServiceError(status_code=502, detail=f"语音识别失败：{detail}") from error
    except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError) as error:
        _log_file_asr_failure(user.id, started_at, len(audio), error)
        raise ServiceError(status_code=502, detail="语音识别服务暂时不可用") from error
    if not text:
        _log_file_asr_failure(user.id, started_at, len(audio), ValueError())
        raise ServiceError(status_code=422, detail="没有识别到清晰的语音")
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
    user_id: str, started_at: float, audio_bytes: int, error: Exception
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
