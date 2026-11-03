import json
from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    ForeignKey,
    String,
    Text,
)
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now

from .base import new_id


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
    archived: bool = Field(
        default=False, sa_column=Column(Boolean, nullable=False, server_default="0")
    )
    muted: bool = Field(
        default=False, sa_column=Column(Boolean, nullable=False, server_default="0")
    )
    pinned: bool = Field(
        default=False, sa_column=Column(Boolean, nullable=False, server_default="0")
    )
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
    location_json: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
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

    @property
    def location(self) -> dict | None:
        if not self.location_json:
            return None
        return json.loads(self.location_json)
