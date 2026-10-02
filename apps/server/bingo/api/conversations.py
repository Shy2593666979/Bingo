from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.api.dependencies import CurrentUserDependency, get_session
from bingo.db.models import Conversation
from bingo.db.repositories import ConversationRepository
from bingo.db.time import beijing_now
from bingo.schemas.chat import ConversationResponse, MessageResponse

router = APIRouter(tags=["conversations"])
SessionDependency = Annotated[AsyncSession, Depends(get_session)]


@router.post("/conversations/{conversation_id}/read", status_code=204)
async def mark_conversation_read(
    conversation_id: str, session: SessionDependency, user: CurrentUserDependency
) -> Response:
    conversation = await session.get(Conversation, conversation_id)
    if not conversation or conversation.user_id != user.id:
        raise HTTPException(404, "对话不存在")
    conversation.last_read_at = beijing_now()
    await session.commit()
    return Response(status_code=204)


@router.get("/conversations", response_model=list[ConversationResponse])
async def list_conversations(
    session: SessionDependency,
    user: CurrentUserDependency,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[ConversationResponse]:
    conversations = await ConversationRepository(session, user.id).list_conversations(limit)
    return [
        ConversationResponse.model_validate(conversation, from_attributes=True)
        for conversation in conversations
    ]


@router.get("/conversations/{conversation_id}/messages", response_model=list[MessageResponse])
async def list_messages(
    conversation_id: str,
    session: SessionDependency,
    user: CurrentUserDependency,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[MessageResponse]:
    messages = await ConversationRepository(session, user.id).list_messages(conversation_id, limit)
    return [MessageResponse.model_validate(message, from_attributes=True) for message in messages]
