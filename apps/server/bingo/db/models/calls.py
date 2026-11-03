from datetime import datetime

from sqlalchemy import (
    Column,
    ForeignKey,
    String,
)
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now

from .base import new_id


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
