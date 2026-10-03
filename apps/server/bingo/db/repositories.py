from datetime import datetime, timedelta

from sqlalchemy import delete, or_
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    AuthSession,
    CallInvitation,
    Conversation,
    DeviceAction,
    Memory,
    MemoryCheckpoint,
    Message,
    ProactiveMessage,
    PushDevice,
    PushOutbox,
    Role,
    RolePreference,
    User,
)
from bingo.db.time import beijing_now
from bingo.services.exceptions import ServiceError
from bingo.services.security import hash_token, new_access_token


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
        if not role or role.deleted or not role.enabled or role.owner_id not in {None, user.id}:
            raise ServiceError(404, "角色已失效，请重新选择")
        preference = await self._session.get(RolePreference, (user.id, role.id))
        return user.model_copy(
            update={
                "role_id": role.id,
                "role": role.visible_name,
                "assistant_name": role.nickname,
                "personality": preference.personality if preference else user.personality,
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


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_phone(self, phone: str) -> User | None:
        return (await self._session.exec(select(User).where(User.phone == phone))).first()

    async def get(self, user_id: str) -> User | None:
        return await self._session.get(User, user_id)

    async def create(self, phone: str, password_hash: str) -> User:
        user = User(phone=phone, password_hash=password_hash)
        self._session.add(user)
        await self._session.commit()
        await self._session.refresh(user)
        return user

    async def update_profile(
        self,
        user: User,
        *,
        username: str,
        assistant_name: str,
        personality: str,
        role: str,
    ) -> User:
        roles = RoleRepository(self._session)
        selected_role = await roles.get(role) or await roles.get_by_name(role)
        if (
            selected_role is None
            or not selected_role.enabled
            or selected_role.deleted
            or selected_role.owner_id not in {None, user.id}
        ):
            raise ValueError("Invalid assistant role")
        if user.role_id != selected_role.id:
            user.role_changed_at = beijing_now()
        user.role_id = selected_role.id
        user.username = username
        user.assistant_name = assistant_name
        user.personality = personality
        user.role = selected_role.visible_name
        user.onboarding_complete = True
        await self._session.commit()
        await self._session.refresh(user)
        return user


class RoleRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_name(self, name: str) -> Role | None:
        if name == "小孩":
            name = "小朋友"
        return (
            await self._session.exec(
                select(Role).where(
                    Role.name == name, Role.owner_id.is_(None), Role.deleted.is_(False)
                )
            )
        ).first()

    async def get(self, role_id: str | None) -> Role | None:
        if role_id is None:
            return None
        return await self._session.get(Role, role_id)

    async def list_enabled(self, user_id: str | None = None) -> list[Role]:
        statement = (
            select(Role)
            .where(
                Role.enabled.is_(True),
                Role.deleted.is_(False),
                or_(Role.owner_id.is_(None), Role.owner_id == user_id),
            )
            .order_by(Role.sort_order, Role.name)
        )
        return list((await self._session.exec(statement)).all())


class AuthSessionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(self, user_id: str, lifetime_days: int = 90) -> str:
        token = new_access_token()
        auth_session = AuthSession(
            user_id=user_id,
            token_hash=hash_token(token),
            expires_at=beijing_now() + timedelta(days=lifetime_days),
        )
        self._session.add(auth_session)
        await self._session.commit()
        return token

    async def get_user(self, token: str) -> User | None:
        statement = (
            select(User)
            .join(AuthSession, AuthSession.user_id == User.id)
            .where(
                AuthSession.token_hash == hash_token(token),
                AuthSession.expires_at > beijing_now(),
            )
        )
        return (await self._session.exec(statement)).first()

    async def delete(self, token: str) -> None:
        await self._session.exec(
            delete(AuthSession).where(AuthSession.token_hash == hash_token(token))
        )
        await self._session.commit()


class DeviceActionRepository:
    def __init__(self, session: AsyncSession, user_id: str) -> None:
        self._session = session
        self._user_id = user_id

    async def create(self, tool_name: str, arguments_json: str) -> DeviceAction:
        action = DeviceAction(
            user_id=self._user_id,
            tool_name=tool_name,
            arguments_json=arguments_json,
        )
        self._session.add(action)
        await self._session.commit()
        await self._session.refresh(action)
        return action

    async def get(self, action_id: str) -> DeviceAction | None:
        return (
            await self._session.exec(
                select(DeviceAction).where(
                    DeviceAction.id == action_id,
                    DeviceAction.user_id == self._user_id,
                )
            )
        ).first()

    async def set_status(
        self, action: DeviceAction, status: str, result: str | None = None
    ) -> DeviceAction:
        action.status = status
        action.result = result
        await self._session.commit()
        await self._session.refresh(action)
        return action


class CallInvitationRepository:
    def __init__(self, session: AsyncSession, user_id: str) -> None:
        self._session = session
        self._user_id = user_id

    async def create(
        self,
        *,
        conversation_id: str,
        role_id: str | None,
        caller_name: str,
        caller_role: str | None,
        reason: str,
        lifetime_seconds: int = 30,
        cooldown_seconds: int = 15,
    ) -> CallInvitation:
        now = beijing_now()
        latest = (
            await self._session.exec(
                select(CallInvitation)
                .where(CallInvitation.user_id == self._user_id)
                .order_by(CallInvitation.created_at.desc())
                .limit(1)
            )
        ).first()
        if latest is not None and latest.status == "ringing":
            if latest.expires_at > now:
                return latest
            latest.status = "missed"
            latest.ended_at = now
        if (
            latest is not None
            and latest.status != "ringing"
            and latest.created_at > now - timedelta(seconds=cooldown_seconds)
        ):
            raise ValueError("刚刚已经发起过来电，请稍后再试")

        invitation = CallInvitation(
            user_id=self._user_id,
            conversation_id=conversation_id,
            role_id=role_id,
            caller_name=caller_name,
            caller_role=caller_role,
            reason=reason,
            expires_at=now + timedelta(seconds=lifetime_seconds),
        )
        self._session.add(invitation)
        await self._session.commit()
        await self._session.refresh(invitation)
        return invitation

    async def get(self, invitation_id: str) -> CallInvitation | None:
        return (
            await self._session.exec(
                select(CallInvitation).where(
                    CallInvitation.id == invitation_id,
                    CallInvitation.user_id == self._user_id,
                )
            )
        ).first()

    async def pending(self) -> CallInvitation | None:
        invitation = (
            await self._session.exec(
                select(CallInvitation)
                .where(
                    CallInvitation.user_id == self._user_id,
                    CallInvitation.status == "ringing",
                )
                .order_by(CallInvitation.created_at.desc())
                .limit(1)
            )
        ).first()
        return await self._expire_if_needed(invitation)

    async def set_status(self, invitation: CallInvitation, status: str) -> CallInvitation:
        now = beijing_now()
        invitation.status = status
        if status == "accepted":
            invitation.answered_at = now
        if status in {"rejected", "missed", "cancelled", "ended", "failed"}:
            invitation.ended_at = now
        await self._session.commit()
        await self._session.refresh(invitation)
        return invitation

    async def _expire_if_needed(self, invitation: CallInvitation | None) -> CallInvitation | None:
        if (
            invitation is not None
            and invitation.status == "ringing"
            and invitation.expires_at <= beijing_now()
        ):
            return await self.set_status(invitation, "missed")
        return invitation


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


class PushDeviceRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def upsert(
        self,
        *,
        user_id: str,
        installation_id: str,
        provider: str,
        client_id: str,
        manufacturer: str | None,
        model: str | None,
        app_version: str | None,
    ) -> PushDevice:
        device = (
            await self._session.exec(
                select(PushDevice).where(PushDevice.installation_id == installation_id)
            )
        ).first()
        now = beijing_now()
        if device is None:
            device = PushDevice(
                user_id=user_id,
                installation_id=installation_id,
                provider=provider,
                client_id=client_id,
                manufacturer=manufacturer,
                model=model,
                app_version=app_version,
            )
            self._session.add(device)
        else:
            device.user_id = user_id
            device.provider = provider
            device.client_id = client_id
            device.manufacturer = manufacturer
            device.model = model
            device.app_version = app_version
            device.active = True
            device.last_seen_at = now
        await self._session.commit()
        await self._session.refresh(device)
        return device

    async def deactivate(self, user_id: str, installation_id: str) -> None:
        device = (
            await self._session.exec(
                select(PushDevice).where(
                    PushDevice.user_id == user_id,
                    PushDevice.installation_id == installation_id,
                )
            )
        ).first()
        if device is not None:
            device.active = False
            await self._session.commit()


class PushOutboxRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def enqueue_for_user(
        self,
        *,
        user_id: str,
        proactive_message_id: str,
        title: str,
        body: str,
        payload_json: str,
    ) -> int:
        devices = list(
            (
                await self._session.exec(
                    select(PushDevice).where(
                        PushDevice.user_id == user_id,
                        PushDevice.active.is_(True),
                    )
                )
            ).all()
        )
        for device in devices:
            self._session.add(
                PushOutbox(
                    user_id=user_id,
                    device_id=device.id,
                    proactive_message_id=proactive_message_id,
                    title=title,
                    body=body,
                    payload_json=payload_json,
                )
            )
        await self._session.commit()
        return len(devices)

    async def next_due(self) -> tuple[PushOutbox, PushDevice] | None:
        statement = (
            select(PushOutbox, PushDevice)
            .join(PushDevice, PushDevice.id == PushOutbox.device_id)
            .where(
                PushOutbox.status == "pending",
                PushOutbox.next_attempt_at <= beijing_now(),
                PushDevice.active.is_(True),
            )
            .order_by(PushOutbox.next_attempt_at, PushOutbox.created_at)
            .limit(1)
        )
        return (await self._session.exec(statement)).first()

    async def mark_sent(self, outbox: PushOutbox, provider_message_id: str | None) -> None:
        outbox.status = "sent"
        outbox.provider_message_id = provider_message_id
        outbox.sent_at = beijing_now()
        outbox.last_error = None
        await self._session.commit()

    async def reschedule(
        self,
        outbox: PushOutbox,
        attempts: int,
        next_attempt_at: datetime,
        error: str,
    ) -> None:
        outbox.attempts = attempts
        outbox.next_attempt_at = next_attempt_at
        outbox.last_error = error[:2000]
        await self._session.commit()

    async def mark_failed(self, outbox: PushOutbox, attempts: int, error: str) -> None:
        outbox.status = "failed"
        outbox.attempts = attempts
        outbox.last_error = error[:2000]
        await self._session.commit()
