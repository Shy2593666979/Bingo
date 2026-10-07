import json

from fastapi import APIRouter, Request
from fastapi.responses import FileResponse, StreamingResponse

from bingo.api.dependencies import CurrentUserDependency, SessionDependency, get_service_context
from bingo.api.response import EnvelopeRoute
from bingo.schemas.chat import ChatRequest, ChatResponse
from bingo.services import chat as chat_service

router = APIRouter(tags=["chat"], route_class=EnvelopeRoute)


@router.post("/chat/speech/{run_id}/stop")
async def stop_speech(run_id: str, request: Request, user: CurrentUserDependency):
    await get_service_context(request).chat_speech.stop(user.id, run_id)
    return {"stopped": True}


@router.post("/chat", response_model=ChatResponse)
async def create_chat(
    payload: ChatRequest, request: Request, session: SessionDependency, user: CurrentUserDependency
) -> ChatResponse:
    return await chat_service.create_chat(payload, get_service_context(request), session, user)


@router.get("/chat/images/{image_id}")
async def get_chat_image(
    image_id: str, session: SessionDependency, user: CurrentUserDependency
) -> FileResponse:
    path, mime = await chat_service.get_chat_image(image_id, session, user)
    return FileResponse(path, media_type=mime)


@router.post("/chat/stream")
async def stream_chat(
    payload: ChatRequest, request: Request, user: CurrentUserDependency
) -> StreamingResponse:
    subscription = await chat_service.subscribe_chat(payload, get_service_context(request), user)

    async def event_stream():
        try:
            async for event in subscription.events():
                yield json.dumps(event, ensure_ascii=False) + "\n"
        finally:
            await subscription.close()

    return StreamingResponse(
        event_stream(),
        media_type="application/x-ndjson",
        headers={"Cache-Control": "no-cache, no-transform", "X-Accel-Buffering": "no"},
    )
