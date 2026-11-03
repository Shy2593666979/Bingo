from datetime import datetime

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

from .base import new_id


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
