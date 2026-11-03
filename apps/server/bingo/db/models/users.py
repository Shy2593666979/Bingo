from datetime import datetime

from sqlalchemy import (
    Column,
    ForeignKey,
    String,
    Text,
)
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now

from .base import new_id


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
    selective_companions: bool = Field(default=False)
    companion_selection_complete: bool = Field(default=True)
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
