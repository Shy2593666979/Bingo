from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.api.dependencies import CurrentUserDependency, get_session
from bingo.api.response import EnvelopeRoute
from bingo.schemas.chat import MemoryCreate, MemoryResponse
from bingo.services import memories as memories_service

router = APIRouter(tags=["memories"], route_class=EnvelopeRoute)
SessionDependency = Annotated[AsyncSession, Depends(get_session)]


@router.get("/memories", response_model=list[MemoryResponse])
async def list_memories(
    session: SessionDependency,
    user: CurrentUserDependency,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[MemoryResponse]:
    return await memories_service.list_memories(session=session, user=user, limit=limit)


@router.post("/memories", response_model=MemoryResponse, status_code=status.HTTP_201_CREATED)
async def create_memory(
    payload: MemoryCreate, session: SessionDependency, user: CurrentUserDependency
) -> MemoryResponse:
    return await memories_service.create_memory(payload=payload, session=session, user=user)


@router.delete("/memories/{memory_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_memory(
    memory_id: str, session: SessionDependency, user: CurrentUserDependency
) -> Response:
    await memories_service.delete_memory(memory_id=memory_id, session=session, user=user)
    return Response(status_code=204)
