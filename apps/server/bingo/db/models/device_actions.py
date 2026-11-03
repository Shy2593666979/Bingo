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


class DeviceAction(SQLModel, table=True):
    __tablename__ = "device_actions"

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    user_id: str = Field(
        sa_column=Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    )
    tool_name: str = Field(max_length=80, index=True)
    arguments_json: str = Field(sa_column=Column(Text, nullable=False))
    conversation_id: str | None = Field(default=None, index=True, max_length=36)
    status: str = Field(default="pending", max_length=20, index=True)
    result: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
    created_at: datetime = Field(
        default_factory=beijing_now,
        sa_column=Column(BeijingDateTime(), nullable=False, index=True),
    )
