from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.api.dependencies import CurrentUserDependency, get_session
from bingo.api.response import EnvelopeRoute
from bingo.schemas.chat import ConversationResponse, MessageResponse
from bingo.services import conversations as conversations_service

router = APIRouter(tags=["conversations"], route_class=EnvelopeRoute)
SessionDependency = Annotated[AsyncSession, Depends(get_session)]


@router.post("/conversations/{conversation_id}/read", status_code=204)
async def mark_conversation_read(
    conversation_id: str, session: SessionDependency, user: CurrentUserDependency
) -> Response:
    await conversations_service.mark_conversation_read(
        conversation_id=conversation_id, session=session, user=user
    )
    return Response(status_code=204)


@router.get("/conversations", response_model=list[ConversationResponse])
async def list_conversations(
    session: SessionDependency,
    user: CurrentUserDependency,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[ConversationResponse]:
    return await conversations_service.list_conversations(session=session, user=user, limit=limit)


@router.get("/conversations/{conversation_id}/messages", response_model=list[MessageResponse])
async def list_messages(
    conversation_id: str,
    session: SessionDependency,
    user: CurrentUserDependency,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[MessageResponse]:
    return await conversations_service.list_messages(
        conversation_id=conversation_id, session=session, user=user, limit=limit
    )
