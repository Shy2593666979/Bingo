from sqlalchemy import delete, or_
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    Conversation,
    Memory,
    MemoryCheckpoint,
    Message,
)
from bingo.db.time import beijing_now


class MemoryCheckpointRepository:
    def __init__(self, session: AsyncSession, user_id: str) -> None:
        self._session = session
        self._user_id = user_id

    async def pending_messages(
        self,
        conversation_id: str,
        completed_message_id: str,
        role_id: str | None,
    ) -> list[Message]:
        statement = (
            select(Message)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(
                Message.conversation_id == conversation_id,
                Conversation.user_id == self._user_id,
                Message.status != "streaming",
                Message.message_type == "chat",
            )
            .order_by(Message.created_at, Message.id)
        )
        messages = list((await self._session.exec(statement)).all())
        checkpoint = await self._get(conversation_id, role_id)
        start = 0
        if checkpoint is not None:
            start = next(
                (
                    index + 1
                    for index, message in enumerate(messages)
                    if message.id == checkpoint.last_message_id
                ),
                0,
            )
        end = next(
            (
                index + 1
                for index, message in enumerate(messages)
                if message.id == completed_message_id
            ),
            0,
        )
        if end == 0 or end <= start:
            return []
        return [message for message in messages[start:end] if message.role_id in {None, role_id}]

    async def advance(
        self,
        conversation_id: str,
        role_id: str | None,
        last_message_id: str,
    ) -> None:
        checkpoint = await self._get(conversation_id, role_id)
        if checkpoint is None:
            checkpoint = MemoryCheckpoint(
                user_id=self._user_id,
                conversation_id=conversation_id,
                role_id=role_id,
                last_message_id=last_message_id,
            )
            self._session.add(checkpoint)
        else:
            checkpoint.last_message_id = last_message_id
            checkpoint.updated_at = beijing_now()
        await self._session.commit()

    async def _get(self, conversation_id: str, role_id: str | None) -> MemoryCheckpoint | None:
        role_filter = (
            MemoryCheckpoint.role_id.is_(None)
            if role_id is None
            else MemoryCheckpoint.role_id == role_id
        )
        return (
            await self._session.exec(
                select(MemoryCheckpoint).where(
                    MemoryCheckpoint.user_id == self._user_id,
                    MemoryCheckpoint.conversation_id == conversation_id,
                    role_filter,
                )
            )
        ).first()


class MemoryRepository:
    def __init__(self, session: AsyncSession, user_id: str) -> None:
        self._session = session
        self._user_id = user_id

    async def list(self, limit: int = 50, role_id: str | None = None) -> list[Memory]:
        filters = [Memory.user_id == self._user_id]
        if role_id is None:
            filters.append(Memory.scope == "user")
        else:
            filters.append(or_(Memory.scope == "user", Memory.role_id == role_id))
        statement = select(Memory).where(*filters).order_by(Memory.created_at.desc()).limit(limit)
        return list((await self._session.exec(statement)).all())

    async def add(
        self,
        content: str,
        category: str = "fact",
        *,
        scope: str = "user",
        role_id: str | None = None,
    ) -> Memory:
        if scope not in {"user", "role", "user_role"}:
            raise ValueError("Invalid memory scope")
        if scope == "user":
            role_id = None
        elif role_id is None:
            raise ValueError("Role-scoped memories require role_id")
        existing = (
            await self._session.exec(
                select(Memory).where(
                    Memory.user_id == self._user_id,
                    Memory.content == content,
                    Memory.scope == scope,
                    Memory.role_id == role_id,
                )
            )
        ).first()
        if existing is not None:
            return existing
        memory = Memory(
            user_id=self._user_id,
            role_id=role_id,
            scope=scope,
            content=content,
            category=category,
        )
        self._session.add(memory)
        await self._session.commit()
        await self._session.refresh(memory)
        return memory

    async def delete(self, memory_id: str) -> bool:
        result = await self._session.exec(
            delete(Memory).where(
                Memory.id == memory_id,
                Memory.user_id == self._user_id,
            )
        )
        await self._session.commit()
        return bool(result.rowcount)
