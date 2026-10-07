import base64
import binascii
from pathlib import Path
from uuid import uuid4

from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.agent.runtime import AgentRuntime
from bingo.db.models import Conversation, Message, User
from bingo.db.repositories import ConversationRepository, RoleRepository
from bingo.schemas.chat import ChatImageInput, ChatRequest, ChatResponse
from bingo.services.chat_runs import ChatRunService
from bingo.services.context import ServiceContext
from bingo.services.exceptions import ServiceError

IMAGE_DIRECTORY = Path(__file__).resolve().parents[2] / "data" / "images"


async def create_chat(
    payload: ChatRequest, context: ServiceContext, session: AsyncSession, user: User
) -> ChatResponse:
    _require_completed_profile(user.onboarding_complete)
    image_data_urls, image_id, image_mime_type = _save_images(payload.images)
    runtime: AgentRuntime = context.runtime
    result = await runtime.run(
        session,
        user,
        payload.content.strip(),
        payload.conversation_id,
        image_data_urls=image_data_urls,
        image_id=image_id,
        image_mime_type=image_mime_type,
        location=payload.location,
    )
    return ChatResponse(
        conversation_id=result.conversation_id, message_id=result.message_id, content=result.content
    )


async def get_chat_image(image_id: str, session: AsyncSession, user: User):
    message = (
        await session.exec(
            select(Message)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(Message.image_id == image_id, Conversation.user_id == user.id)
        )
    ).first()
    if message is None:
        raise ServiceError(status_code=404, detail="图片不存在")
    path = IMAGE_DIRECTORY / f"{image_id}.jpg"
    if not path.is_file():
        raise ServiceError(status_code=404, detail="图片文件不存在")
    return (path, message.image_mime_type or "image/jpeg")


async def subscribe_chat(payload: ChatRequest, context: ServiceContext, user: User):
    _require_completed_profile(user.onboarding_complete)
    image_data_urls, image_id, image_mime_type = _save_images(payload.images)
    run_id = payload.run_id or uuid4().hex
    voice = context.settings.realtime_call.voice
    if payload.read_aloud:
        async with context.database.session_factory() as session:
            context_user = await ConversationRepository(session, user.id).context_user(
                user, payload.conversation_id
            )
            role = await RoleRepository(session).get(context_user.role_id)
            if role:
                voice = role.voice or voice
    chat_runs: ChatRunService = context.chat_runs
    subscription = await chat_runs.subscribe(
        user_id=user.id,
        run_id=run_id,
        supersedes_run_id=payload.supersedes_run_id,
        content=payload.content.strip(),
        conversation_id=payload.conversation_id,
        image_data_urls=image_data_urls,
        image_id=image_id,
        image_mime_type=image_mime_type,
        location=payload.location,
        include_text_deltas=payload.read_aloud,
    )
    if payload.read_aloud:
        return SpokenSubscription(subscription, context.chat_speech, user.id, run_id, voice)
    return subscription


class SpokenSubscription:
    def __init__(self, subscription, speech, user_id, run_id, voice):
        self.subscription = subscription
        self.speech = speech
        self.user_id = user_id
        self.run_id = run_id
        self.voice = voice

    def events(self):
        return self.speech.events(self.subscription, self.user_id, self.run_id, self.voice)

    async def close(self):
        await self.speech.stop(self.user_id, self.run_id)
        await self.subscription.close()


def _require_completed_profile(completed: bool) -> None:
    if not completed:
        raise ServiceError(status_code=403, detail="请先完成用户名和助手个性设置")


def _validate_image_signature(image: bytes, mime_type: str) -> None:
    signatures = {
        "image/jpeg": (b"\xff\xd8\xff",),
        "image/png": (b"\x89PNG\r\n\x1a\n",),
        "image/webp": (b"RIFF",),
    }
    valid = any(image.startswith(signature) for signature in signatures[mime_type])
    if mime_type == "image/webp":
        valid = valid and len(image) >= 12 and (image[8:12] == b"WEBP")
    if not valid:
        raise ServiceError(status_code=422, detail="图片格式与 mime_type 不匹配")


def _save_images(images: list[ChatImageInput]) -> tuple[tuple[str, ...], str | None, str | None]:
    if not images:
        return ((), None, None)
    image = images[0]
    try:
        image_bytes = base64.b64decode(image.data, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ServiceError(status_code=422, detail="图片数据不是有效的 Base64") from error
    if not image_bytes:
        raise ServiceError(status_code=422, detail="图片不能为空")
    if len(image_bytes) > 5000000:
        raise ServiceError(status_code=413, detail="图片不能超过 5 MB")
    _validate_image_signature(image_bytes, image.mime_type)
    image_id = str(uuid4())
    IMAGE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    (IMAGE_DIRECTORY / f"{image_id}.jpg").write_bytes(image_bytes)
    data_url = f"data:{image.mime_type};base64,{image.data}"
    return ((data_url,), image_id, image.mime_type)
