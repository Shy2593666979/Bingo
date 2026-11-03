from sqlmodel import delete, select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    CallInvitation,
    Conversation,
    DeviceAction,
    MemoryCheckpoint,
    Message,
    ProactiveMessage,
    PushOutbox,
    User,
)
from bingo.db.repositories import ConversationRepository
from bingo.db.time import beijing_now
from bingo.schemas.chat import (
    ChatSettings,
    ChatSettingsUpdate,
    ConversationResponse,
    MessageResponse,
)
from bingo.services.context import ServiceContext
from bingo.services.device_actions import device_action_response
from bingo.services.exceptions import ServiceError


async def owned_conversation(
    conversation_id: str, session: AsyncSession, user: User
) -> Conversation:
    conversation = await session.get(Conversation, conversation_id)
    if not conversation or conversation.user_id != user.id:
        raise ServiceError(404, "对话不存在")
    return conversation


async def get_chat_settings(
    conversation_id: str, session: AsyncSession, user: User
) -> ChatSettings:
    conversation = await owned_conversation(conversation_id, session, user)
    return ChatSettings.model_validate(conversation, from_attributes=True)


async def update_chat_settings(
    conversation_id: str, payload: ChatSettingsUpdate, session: AsyncSession, user: User
) -> ChatSettings:
    conversation = await owned_conversation(conversation_id, session, user)
    for key, value in payload.model_dump(exclude_none=True).items():
        setattr(conversation, key, value)
    await session.commit()
    return ChatSettings.model_validate(conversation, from_attributes=True)


async def clear_messages(
    conversation_id: str, session: AsyncSession, user: User, context: ServiceContext
) -> None:
    conversation = await owned_conversation(conversation_id, session, user)
    streaming = (
        await session.exec(
            select(Message.id)
            .where(Message.conversation_id == conversation_id, Message.status == "streaming")
            .limit(1)
        )
    ).first()
    call = (
        await session.exec(
            select(CallInvitation.id)
            .where(
                CallInvitation.conversation_id == conversation_id,
                (CallInvitation.status == "accepted")
                | (
                    (CallInvitation.status == "ringing")
                    & (CallInvitation.expires_at > beijing_now())
                ),
            )
            .limit(1)
        )
    ).first()
    if streaming or call:
        raise ServiceError(409, "请等当前回复或通话结束后再清空")
    if context.engagement is not None:
        await context.engagement.reset_conversation(user.id, conversation_id)
    proactive_ids = select(ProactiveMessage.id).where(
        ProactiveMessage.conversation_id == conversation_id
    )
    await session.exec(delete(PushOutbox).where(PushOutbox.proactive_message_id.in_(proactive_ids)))
    await session.exec(
        delete(ProactiveMessage).where(ProactiveMessage.conversation_id == conversation_id)
    )
    await session.exec(
        delete(MemoryCheckpoint).where(MemoryCheckpoint.conversation_id == conversation_id)
    )
    await session.exec(delete(DeviceAction).where(DeviceAction.conversation_id == conversation_id))
    await session.exec(delete(Message).where(Message.conversation_id == conversation_id))
    conversation.last_read_at = beijing_now()
    await session.commit()


async def mark_conversation_read(conversation_id: str, session: AsyncSession, user: User) -> None:
    conversation = await session.get(Conversation, conversation_id)
    if not conversation or conversation.user_id != user.id:
        raise ServiceError(404, "对话不存在")
    conversation.last_read_at = beijing_now()
    await session.commit()
    return None


async def list_conversations(
    session: AsyncSession, user: User, limit: int = 50
) -> list[ConversationResponse]:
    conversations = await ConversationRepository(session, user.id).list_conversations(limit)
    return [
        ConversationResponse.model_validate(conversation, from_attributes=True)
        for conversation in conversations
    ]


async def list_messages(
    conversation_id: str,
    session: AsyncSession,
    user: User,
    limit: int = 50,
    query: str | None = None,
) -> list[MessageResponse]:
    if query is not None:
        await owned_conversation(conversation_id, session, user)
        query = query.strip()
        if not query:
            return []
        messages = list(
            (
                await session.exec(
                    select(Message)
                    .where(
                        Message.conversation_id == conversation_id,
                        Message.content.contains(query, autoescape=True),
                        Message.status != "streaming",
                    )
                    .order_by(Message.created_at.desc())
                    .limit(limit)
                )
            ).all()
        )
    else:
        messages = await ConversationRepository(session, user.id).list_messages(
            conversation_id, limit
        )
    action_ids = [message.id for message in messages if message.message_type == "device_action"]
    actions = (
        (
            await session.exec(
                select(DeviceAction).where(
                    DeviceAction.id.in_(action_ids), DeviceAction.user_id == user.id
                )
            )
        ).all()
        if action_ids
        else []
    )
    by_id = {action.id: action for action in actions}
    return [
        MessageResponse.model_validate(message, from_attributes=True).model_copy(
            update={
                "device_action": (
                    device_action_response(by_id[message.id]) if message.id in by_id else None
                )
            }
        )
        for message in messages
    ]
