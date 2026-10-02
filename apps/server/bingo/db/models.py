from datetime import datetime
from uuid import uuid4

from sqlalchemy import (
    Boolean,
    Column,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now
from bingo.roles.catalog import BUILTIN_NICKNAMES


def new_id() -> str:
    return str(uuid4())


class Role(SQLModel, table=True):
    __tablename__ = "roles"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    code: str = Field(max_length=40, unique=True, index=True)
    name: str = Field(max_length=30, unique=True, index=True)
    description: str = Field(default="", sa_column=Column(Text, nullable=False))
    prompt: str = Field(default="", sa_column=Column(Text, nullable=False))
    avatar: str = Field(max_length=255)
    voice: str = Field(default="", max_length=255)
    enabled: bool = Field(default=True, sa_column=Column(Boolean, nullable=False, index=True))
    sort_order: int = Field(default=0, sa_column=Column(Integer, nullable=False))
    owner_id: str | None = Field(default=None, index=True, max_length=36)
    display_name: str | None = Field(default=None, max_length=30)
    role_type: str | None = Field(default=None, max_length=30)
    avatar_data: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
    voice_source_id: str | None = Field(default=None, max_length=36, index=True)
    owned_voice: str = Field(default="", max_length=255)
    deleted: bool = Field(default=False)
    categories_json: str = Field(default='["陪伴", "朋友"]', sa_column=Column(Text, nullable=False))
    traits_json: str = Field(
        default='["善于倾听", "陪伴聊天"]', sa_column=Column(Text, nullable=False)
    )

    @property
    def visible_name(self) -> str:
        return self.display_name or self.name

    @property
    def nickname(self) -> str:
        if self.owner_id is None:
            return BUILTIN_NICKNAMES.get(self.code, self.visible_name)
        return self.visible_name

    @property
    def context_prompt(self) -> str:
        if self.owner_id is None or self.role_type is None:
            return self.prompt
        identity = self.role_type or "陪伴伙伴，没有固定的角色身份"
        return f"你的伙伴角色是{identity}。\n{self.prompt}"

    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )
    updated_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )


class RolePreference(SQLModel, table=True):
    __tablename__ = "role_preferences"

    user_id: str = Field(primary_key=True, max_length=36)
    role_id: str = Field(primary_key=True, max_length=36)
    personality: str = Field(max_length=30)


class VoiceJob(SQLModel, table=True):
    __tablename__ = "voice_jobs"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(index=True, max_length=36)
    role_id: str = Field(index=True, max_length=36)
    kind: str = Field(default="clone", max_length=20)
    status: str = Field(default="pending", max_length=20, index=True)
    voice: str = Field(default="", max_length=255)
    error: str | None = Field(default=None, max_length=255)
    sample: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
    sample_token: str | None = Field(default=None, max_length=100, index=True)
    public_base_url: str = Field(default="", max_length=255)
    created_at: datetime = Field(default_factory=beijing_now, sa_column=Column(BeijingDateTime()))


class User(SQLModel, table=True):
    __tablename__ = "users"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    phone: str = Field(max_length=20, unique=True, index=True)
    password_hash: str = Field(max_length=255)
    username: str | None = Field(default=None, max_length=30)
    birthday: str | None = Field(default=None, max_length=10)
    gender: str | None = Field(default=None, max_length=10)
    user_avatar_data: str | None = Field(default=None, sa_column=Column(Text))
    recovery_hash: str | None = Field(default=None, max_length=64)
    assistant_name: str | None = Field(default=None, max_length=30)
    personality: str | None = Field(default=None, max_length=30)
    role_id: str | None = Field(
        default=None,
        sa_column=Column(
            String(36), ForeignKey("roles.id", ondelete="SET NULL"), nullable=True, index=True
        ),
    )
    # Deprecated compatibility value for clients created before roles became data-driven.
    role: str | None = Field(default=None, max_length=30)
    # Kept for compatibility with databases created before role replaced tone.
    tone: str | None = Field(default=None, max_length=30)
    onboarding_complete: bool = Field(default=False)
    role_changed_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )


class AuthSession(SQLModel, table=True):
    __tablename__ = "auth_sessions"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(
        sa_column=Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    )
    token_hash: str = Field(max_length=64, unique=True, index=True)
    expires_at: datetime = Field(sa_column=Column(BeijingDateTime(), nullable=False, index=True))
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )


class DeviceAction(SQLModel, table=True):
    __tablename__ = "device_actions"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(
        sa_column=Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    )
    tool_name: str = Field(max_length=80, index=True)
    arguments_json: str = Field(sa_column=Column(Text, nullable=False))
    status: str = Field(default="pending", max_length=20, index=True)
    result: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False, index=True),
    )


class Conversation(SQLModel, table=True):
    __tablename__ = "conversations"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str | None = Field(
        default=None,
        sa_column=Column(
            String(36),
            ForeignKey("users.id", ondelete="CASCADE"),
            nullable=True,
            index=True,
        ),
    )
    title: str = Field(default="New conversation", max_length=200)
    role_id: str | None = Field(default=None, foreign_key="roles.id", index=True)
    last_read_at: datetime | None = Field(
        default=None, sa_column=Column(BeijingDateTime(), nullable=True)
    )
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )


class Message(SQLModel, table=True):
    __tablename__ = "messages"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    conversation_id: str = Field(
        sa_column=Column(
            String(36),
            ForeignKey("conversations.id", ondelete="CASCADE"),
            index=True,
        )
    )
    role: str = Field(max_length=20)
    message_type: str = Field(default="chat", max_length=20, index=True)
    content: str = Field(sa_column=Column(Text, nullable=False))
    image_id: str | None = Field(default=None, max_length=36, unique=True, index=True)
    image_mime_type: str | None = Field(default=None, max_length=40)
    assistant_role: str | None = Field(default=None, max_length=30)
    role_id: str | None = Field(
        default=None,
        sa_column=Column(String(36), ForeignKey("roles.id", ondelete="SET NULL"), index=True),
    )
    run_id: str | None = Field(default=None, max_length=80, index=True)
    status: str = Field(default="completed", max_length=20, index=True)
    call_status: str | None = Field(default=None, max_length=20)
    call_duration_seconds: int | None = Field(default=None, ge=0)
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False, index=True),
    )


class MemoryCheckpoint(SQLModel, table=True):
    __tablename__ = "memory_checkpoints"
    __table_args__ = (UniqueConstraint("user_id", "conversation_id", "role_id"),)

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(
        sa_column=Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    )
    conversation_id: str = Field(
        sa_column=Column(
            String(36),
            ForeignKey("conversations.id", ondelete="CASCADE"),
            index=True,
        )
    )
    role_id: str | None = Field(
        default=None,
        sa_column=Column(String(36), ForeignKey("roles.id", ondelete="CASCADE"), index=True),
    )
    last_message_id: str = Field(
        sa_column=Column(String(36), ForeignKey("messages.id", ondelete="CASCADE"))
    )
    updated_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )


class Memory(SQLModel, table=True):
    __tablename__ = "memories"
    __table_args__ = (UniqueConstraint("user_id", "role_id", "scope", "content"),)

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str | None = Field(
        default=None,
        sa_column=Column(
            String(36),
            ForeignKey("users.id", ondelete="CASCADE"),
            nullable=True,
            index=True,
        ),
    )
    content: str = Field(sa_column=Column(Text, nullable=False))
    category: str = Field(default="fact", max_length=30)
    scope: str = Field(default="user", max_length=20, index=True)
    role_id: str | None = Field(
        default=None,
        sa_column=Column(
            String(36), ForeignKey("roles.id", ondelete="CASCADE"), nullable=True, index=True
        ),
    )
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False, index=True),
    )


class ProactiveMessage(SQLModel, table=True):
    __tablename__ = "proactive_messages"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(
        sa_column=Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    )
    conversation_id: str = Field(
        sa_column=Column(
            String(36),
            ForeignKey("conversations.id", ondelete="CASCADE"),
            index=True,
        )
    )
    message_id: str = Field(
        sa_column=Column(
            String(36),
            ForeignKey("messages.id", ondelete="CASCADE"),
            unique=True,
        )
    )
    stage: int = Field(default=1)
    delivered_at: datetime | None = Field(
        default=None,
        sa_column=Column(BeijingDateTime(), nullable=True),
    )
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False, index=True),
    )


class CallInvitation(SQLModel, table=True):
    __tablename__ = "call_invitations"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(
        sa_column=Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    )
    conversation_id: str = Field(
        sa_column=Column(
            String(36),
            ForeignKey("conversations.id", ondelete="CASCADE"),
            index=True,
        )
    )
    role_id: str | None = Field(
        default=None,
        sa_column=Column(String(36), ForeignKey("roles.id", ondelete="SET NULL"), index=True),
    )
    caller_name: str = Field(max_length=30)
    caller_role: str | None = Field(default=None, max_length=30)
    reason: str = Field(default="想和你说说话", max_length=200)
    initiator: str = Field(default="assistant", max_length=20, index=True)
    status: str = Field(default="ringing", max_length=20, index=True)
    expires_at: datetime = Field(sa_column=Column(BeijingDateTime(), nullable=False, index=True))
    answered_at: datetime | None = Field(
        default=None,
        sa_column=Column(BeijingDateTime(), nullable=True),
    )
    ended_at: datetime | None = Field(
        default=None,
        sa_column=Column(BeijingDateTime(), nullable=True),
    )
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False, index=True),
    )


class PushDevice(SQLModel, table=True):
    __tablename__ = "push_devices"
    __table_args__ = (UniqueConstraint("installation_id"),)

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(
        sa_column=Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    )
    installation_id: str = Field(max_length=100, index=True)
    provider: str = Field(max_length=30, index=True)
    client_id: str = Field(max_length=255, index=True)
    manufacturer: str | None = Field(default=None, max_length=80)
    model: str | None = Field(default=None, max_length=120)
    app_version: str | None = Field(default=None, max_length=40)
    active: bool = Field(default=True, sa_column=Column(Boolean, nullable=False, index=True))
    last_seen_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )


class PushOutbox(SQLModel, table=True):
    __tablename__ = "push_outbox"
    __table_args__ = (UniqueConstraint("proactive_message_id", "device_id"),)

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(
        sa_column=Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    )
    device_id: str = Field(
        sa_column=Column(String(36), ForeignKey("push_devices.id", ondelete="CASCADE"), index=True)
    )
    proactive_message_id: str = Field(
        sa_column=Column(
            String(36),
            ForeignKey("proactive_messages.id", ondelete="CASCADE"),
            index=True,
        )
    )
    title: str = Field(max_length=100)
    body: str = Field(sa_column=Column(Text, nullable=False))
    payload_json: str = Field(sa_column=Column(Text, nullable=False))
    status: str = Field(default="pending", max_length=20, index=True)
    attempts: int = Field(default=0, sa_column=Column(Integer, nullable=False))
    next_attempt_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False, index=True),
    )
    provider_message_id: str | None = Field(default=None, max_length=255)
    last_error: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False),
    )
    sent_at: datetime | None = Field(
        default=None,
        sa_column=Column(BeijingDateTime(), nullable=True),
    )
