from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import Conversation, User
from bingo.db.repositories import ConversationRepository
from bingo.db.time import beijing_now
from bingo.schemas.chat import ConversationResponse, MessageResponse
from bingo.services.exceptions import ServiceError


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
    conversation_id: str, session: AsyncSession, user: User, limit: int = 50
) -> list[MessageResponse]:
    messages = await ConversationRepository(session, user.id).list_messages(conversation_id, limit)
    return [MessageResponse.model_validate(message, from_attributes=True) for message in messages]
