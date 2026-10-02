from fastapi import APIRouter, Request, WebSocket

from bingo.api.dependencies import CurrentUserDependency, get_service_context
from bingo.api.response import EnvelopeRoute
from bingo.services import auth as auth_service
from bingo.services import file_asr
from bingo.services.asr import RealtimeAsrProxy

router = APIRouter(tags=["asr"], route_class=EnvelopeRoute)


@router.websocket("/asr/realtime")
async def realtime_transcribe(websocket: WebSocket) -> None:
    authorization = websocket.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        await websocket.close(code=4401, reason="请先登录")
        return
    user = await auth_service.authenticated_user(websocket.app.state.database, token)
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
async def transcribe_audio(request: Request, user: CurrentUserDependency) -> dict[str, str]:
    return await file_asr.transcribe_audio(
        get_service_context(request),
        user,
        await request.body(),
        request.headers.get("content-type", ""),
    )
