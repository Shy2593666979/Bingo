from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    Message,
    ProactiveMessage,
)
from bingo.db.time import beijing_now


class ProactiveMessageRepository:
    def __init__(self, session: AsyncSession, user_id: str) -> None:
        self._session = session
        self._user_id = user_id

    async def create(
        self,
        conversation_id: str,
        content: str,
        stage: int,
        assistant_role: str | None = None,
        role_id: str | None = None,
    ) -> ProactiveMessage:
        proactive = await self.create_uncommitted(
            conversation_id, content, stage, assistant_role, role_id
        )
        await self._session.commit()
        await self._session.refresh(proactive)
        return proactive

    async def create_uncommitted(
        self,
        conversation_id: str,
        content: str,
        stage: int,
        assistant_role: str | None = None,
        role_id: str | None = None,
    ) -> ProactiveMessage:
        message = Message(
            conversation_id=conversation_id,
            role="assistant",
            content=content,
            assistant_role=assistant_role,
            role_id=role_id,
        )
        self._session.add(message)
        await self._session.flush()
        proactive = ProactiveMessage(
            user_id=self._user_id,
            conversation_id=conversation_id,
            message_id=message.id,
            stage=stage,
        )
        self._session.add(proactive)
        await self._session.flush()
        return proactive

    async def list_pending(self, limit: int = 20) -> list[tuple[ProactiveMessage, Message]]:
        statement = (
            select(ProactiveMessage, Message)
            .join(Message, Message.id == ProactiveMessage.message_id)
            .where(
                ProactiveMessage.user_id == self._user_id,
                ProactiveMessage.delivered_at.is_(None),
            )
            .order_by(ProactiveMessage.created_at)
            .limit(limit)
        )
        return list((await self._session.exec(statement)).all())

    async def acknowledge(self, proactive_id: str) -> bool:
        proactive = (
            await self._session.exec(
                select(ProactiveMessage).where(
                    ProactiveMessage.id == proactive_id,
                    ProactiveMessage.user_id == self._user_id,
                )
            )
        ).first()
        if proactive is None:
            return False
        proactive.delivered_at = beijing_now()
        await self._session.commit()
        return True
