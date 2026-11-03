from datetime import datetime

from sqlalchemy import (
    Column,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
)
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now

from .base import new_id


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
