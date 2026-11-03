from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    Integer,
    Text,
)
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now
from bingo.roles.catalog import BUILTIN_NICKNAMES

from .base import new_id


class Role(SQLModel, table=True):
    __tablename__ = "roles"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    code: str = Field(max_length=40, unique=True, index=True)
    name: str = Field(max_length=30, unique=True, index=True)
    description: str = Field(default="", sa_column=Column(Text, nullable=False))
    opening_line: str = Field(default="", sa_column=Column(Text, nullable=False, server_default=""))
    prompt: str = Field(default="", sa_column=Column(Text, nullable=False))
    avatar: str = Field(max_length=255)
    voice: str = Field(default="", max_length=255)
    enabled: bool = Field(default=True, sa_column=Column(Boolean, nullable=False, index=True))
    sort_order: int = Field(default=0, sa_column=Column(Integer, nullable=False))
    owner_id: str | None = Field(default=None, index=True, max_length=36)
    source_publication_id: str | None = Field(default=None, max_length=36)
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


class UserCompanion(SQLModel, table=True):
    __tablename__ = "user_companions"

    user_id: str = Field(primary_key=True, foreign_key="users.id", ondelete="CASCADE")
    role_id: str = Field(primary_key=True, foreign_key="roles.id", ondelete="CASCADE")


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
