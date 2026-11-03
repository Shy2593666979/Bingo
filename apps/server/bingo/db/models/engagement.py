from datetime import datetime

from sqlalchemy import (
    Column,
    ForeignKey,
    String,
    UniqueConstraint,
)
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now

from .base import new_id


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


class MorningGreeting(SQLModel, table=True):
    __tablename__ = "morning_greetings"
    __table_args__ = (UniqueConstraint("user_id", "partner_key", "greeting_date"),)

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(foreign_key="users.id", index=True)
    conversation_id: str = Field(foreign_key="conversations.id", index=True)
    partner_key: str = Field(max_length=36)
    greeting_date: str = Field(max_length=10, index=True)
    scheduled_at: datetime = Field(sa_column=Column(BeijingDateTime(), nullable=False, index=True))
    status: str = Field(default="pending", max_length=20, index=True)
    attempts: int = Field(default=0)
    claim_until: datetime | None = Field(
        default=None, sa_column=Column(BeijingDateTime(), nullable=True)
    )
