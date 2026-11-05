from datetime import datetime

from sqlmodel import select, update
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    Conversation,
    Message,
    Role,
    RolePreference,
    User,
)
from bingo.roles.persona import speaking_style_for
from bingo.services.exceptions import ServiceError

from .roles import RoleRepository


class ConversationRepository:
    def __init__(self, session: AsyncSession, user_id: str) -> None:
        self._session = session
        self._user_id = user_id

    async def get_or_create(
        self, conversation_id: str | None, role_id: str | None = None
    ) -> Conversation:
        conversation = None
        if conversation_id:
            conversation = (
                await self._session.exec(
                    select(Conversation).where(
                        Conversation.id == conversation_id,
                        Conversation.user_id == self._user_id,
                    )
                )
            ).first()
            if conversation is None:
                raise ServiceError(404, "对话不存在")
        if conversation is not None:
            return conversation
        if role_id is None:
            user = await self._session.get(User, self._user_id)
            role_id = user.role_id if user else None
        conversation = (
            await self._session.exec(
                select(Conversation)
                .where(
                    Conversation.user_id == self._user_id,
                    Conversation.role_id == role_id,
                )
                .order_by(Conversation.created_at.desc())
                .limit(1)
            )
        ).first()
        if conversation is not None:
            return conversation

        conversation = Conversation(user_id=self._user_id, role_id=role_id)
        self._session.add(conversation)
        await self._session.flush()
        return conversation

    async def context_user(self, user: User, conversation_id: str | None) -> User:
        conversation = await self.get_or_create(conversation_id)
        if conversation.role_id is None:
            return user
        role = await self._session.get(Role, conversation.role_id)
        if not await RoleRepository(self._session).can_access(user, role):
            raise ServiceError(404, "角色已失效，请重新选择")
        preference = await self._session.get(RolePreference, (user.id, role.id))
        return user.model_copy(
            update={
                "role_id": role.id,
                "role": role.visible_name,
                "assistant_name": role.nickname,
                "personality": speaking_style_for(role, user.personality, preference),
            }
        )

    async def add_message(
        self,
        conversation_id: str,
        role: str,
        content: str,
        assistant_role: str | None = None,
        role_id: str | None = None,
        run_id: str | None = None,
        status: str = "completed",
        message_type: str = "chat",
        call_status: str | None = None,
        call_duration_seconds: int | None = None,
    ) -> Message:
        await self._session.exec(
            update(Conversation).where(Conversation.id == conversation_id).values(archived=False)
        )
        message = Message(
            conversation_id=conversation_id,
            role=role,
            message_type=message_type,
            content=content,
            assistant_role=assistant_role if role == "assistant" else None,
            role_id=role_id,
            run_id=run_id,
            status=status,
            call_status=call_status,
            call_duration_seconds=call_duration_seconds,
        )
        self._session.add(message)
        await self._session.flush()
        return message

    async def list_messages(
        self,
        conversation_id: str,
        limit: int = 50,
        since: datetime | None = None,
    ) -> list[Message]:
        statement = (
            select(Message)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(
                Message.conversation_id == conversation_id,
                Conversation.user_id == self._user_id,
            )
        )
        if since is not None:
            statement = statement.where(Message.created_at >= since)
        statement = statement.order_by(Message.created_at.desc()).limit(limit)
        messages = list((await self._session.exec(statement)).all())
        messages.reverse()
        return messages

    async def list_conversations(self, limit: int = 50) -> list[Conversation]:
        statement = (
            select(Conversation)
            .where(Conversation.user_id == self._user_id)
            .order_by(Conversation.created_at.desc())
            .limit(limit)
        )
        return list((await self._session.exec(statement)).all())

    async def latest_user_message(self) -> Message | None:
        statement = (
            select(Message)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(
                Conversation.user_id == self._user_id,
                Message.role == "user",
            )
            .order_by(Message.created_at.desc())
            .limit(1)
        )
        return (await self._session.exec(statement)).first()

    async def commit(self) -> None:
        await self._session.commit()
