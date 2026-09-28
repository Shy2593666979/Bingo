from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.api.dependencies import CurrentUserDependency, get_session
from bingo.db.repositories import MemoryRepository
from bingo.schemas.chat import MemoryCreate, MemoryResponse

router = APIRouter(tags=["memories"])
SessionDependency = Annotated[AsyncSession, Depends(get_session)]


@router.get("/memories", response_model=list[MemoryResponse])
async def list_memories(
    session: SessionDependency,
    user: CurrentUserDependency,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[MemoryResponse]:
    memories = await MemoryRepository(session, user.id).list(limit, role_id=user.role_id)
    return [MemoryResponse.model_validate(memory, from_attributes=True) for memory in memories]


@router.post("/memories", response_model=MemoryResponse, status_code=status.HTTP_201_CREATED)
async def create_memory(
    payload: MemoryCreate, session: SessionDependency, user: CurrentUserDependency
) -> MemoryResponse:
    memory = await MemoryRepository(session, user.id).add(payload.content.strip())
    return MemoryResponse.model_validate(memory, from_attributes=True)


@router.delete("/memories/{memory_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_memory(
    memory_id: str, session: SessionDependency, user: CurrentUserDependency
) -> Response:
    if not await MemoryRepository(session, user.id).delete(memory_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Memory not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)
