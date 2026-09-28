import base64
import binascii
import json
from pathlib import Path
from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import FileResponse, StreamingResponse
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.agent.runtime import AgentRuntime
from bingo.api.dependencies import CurrentUserDependency, get_session
from bingo.db.models import Conversation, Message
from bingo.schemas.chat import ChatImageInput, ChatRequest, ChatResponse
from bingo.services.chat_runs import ChatRunService

router = APIRouter(tags=["chat"])
SessionDependency = Annotated[AsyncSession, Depends(get_session)]
IMAGE_DIRECTORY = Path(__file__).resolve().parents[2] / "data" / "images"


@router.post("/chat", response_model=ChatResponse)
async def create_chat(
    payload: ChatRequest,
    request: Request,
    session: SessionDependency,
    user: CurrentUserDependency,
) -> ChatResponse:
    _require_completed_profile(user.onboarding_complete)
    image_data_urls, image_id, image_mime_type = _save_images(payload.images)
    runtime: AgentRuntime = request.app.state.runtime
    result = await runtime.run(
        session,
        user,
        payload.content.strip(),
        payload.conversation_id,
        image_data_urls=image_data_urls,
        image_id=image_id,
        image_mime_type=image_mime_type,
    )
    return ChatResponse(
        conversation_id=result.conversation_id,
        message_id=result.message_id,
        content=result.content,
    )


@router.get("/chat/images/{image_id}")
async def get_chat_image(
    image_id: str,
    session: SessionDependency,
    user: CurrentUserDependency,
) -> FileResponse:
    message = (
        await session.exec(
            select(Message)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(Message.image_id == image_id, Conversation.user_id == user.id)
        )
    ).first()
    if message is None:
        raise HTTPException(status_code=404, detail="图片不存在")
    path = IMAGE_DIRECTORY / f"{image_id}.jpg"
    if not path.is_file():
        raise HTTPException(status_code=404, detail="图片文件不存在")
    return FileResponse(path, media_type=message.image_mime_type or "image/jpeg")


@router.post("/chat/stream")
async def stream_chat(
    payload: ChatRequest,
    request: Request,
    user: CurrentUserDependency,
) -> StreamingResponse:
    _require_completed_profile(user.onboarding_complete)
    image_data_urls, image_id, image_mime_type = _save_images(payload.images)
    run_id = payload.run_id or uuid4().hex
    chat_runs: ChatRunService = request.app.state.chat_runs
    subscription = await chat_runs.subscribe(
        user_id=user.id,
        run_id=run_id,
        supersedes_run_id=payload.supersedes_run_id,
        content=payload.content.strip(),
        conversation_id=payload.conversation_id,
        image_data_urls=image_data_urls,
        image_id=image_id,
        image_mime_type=image_mime_type,
    )

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


def _require_completed_profile(completed: bool) -> None:
    if not completed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="请先完成用户名和助手个性设置",
        )


def _validate_image_signature(image: bytes, mime_type: str) -> None:
    signatures = {
        "image/jpeg": (b"\xff\xd8\xff",),
        "image/png": (b"\x89PNG\r\n\x1a\n",),
        "image/webp": (b"RIFF",),
    }
    valid = any(image.startswith(signature) for signature in signatures[mime_type])
    if mime_type == "image/webp":
        valid = valid and len(image) >= 12 and image[8:12] == b"WEBP"
    if not valid:
        raise HTTPException(status_code=422, detail="图片格式与 mime_type 不匹配")


def _save_images(images: list[ChatImageInput]) -> tuple[tuple[str, ...], str | None, str | None]:
    if not images:
        return (), None, None
    image = images[0]
    try:
        image_bytes = base64.b64decode(image.data, validate=True)
    except (binascii.Error, ValueError) as error:
        raise HTTPException(status_code=422, detail="图片数据不是有效的 Base64") from error
    if not image_bytes:
        raise HTTPException(status_code=422, detail="图片不能为空")
    if len(image_bytes) > 5_000_000:
        raise HTTPException(status_code=413, detail="图片不能超过 5 MB")
    _validate_image_signature(image_bytes, image.mime_type)
    image_id = str(uuid4())
    IMAGE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    (IMAGE_DIRECTORY / f"{image_id}.jpg").write_bytes(image_bytes)
    data_url = f"data:{image.mime_type};base64,{image.data}"
    return (data_url,), image_id, image.mime_type
