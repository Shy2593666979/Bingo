from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import User
from bingo.db.repositories import MemoryRepository
from bingo.schemas.chat import MemoryCreate, MemoryResponse
from bingo.services.exceptions import ServiceError


async def list_memories(session: AsyncSession, user: User, limit: int = 50) -> list[MemoryResponse]:
    memories = await MemoryRepository(session, user.id).list(limit, role_id=user.role_id)
    return [MemoryResponse.model_validate(memory, from_attributes=True) for memory in memories]


async def create_memory(payload: MemoryCreate, session: AsyncSession, user: User) -> MemoryResponse:
    memory = await MemoryRepository(session, user.id).add(payload.content.strip())
    return MemoryResponse.model_validate(memory, from_attributes=True)


async def delete_memory(memory_id: str, session: AsyncSession, user: User) -> None:
    if not await MemoryRepository(session, user.id).delete(memory_id):
        raise ServiceError(status_code=404, detail="Memory not found")
    return None
