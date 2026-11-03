from datetime import datetime

from sqlalchemy import Column, Text, UniqueConstraint
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now

from .base import new_id


class WelcomeJob(SQLModel, table=True):
    __tablename__ = "companion_welcome_jobs"
    __table_args__ = (UniqueConstraint("user_id", "role_id"),)
    id: str = Field(default_factory=new_id, primary_key=True)
    user_id: str = Field(index=True)
    role_id: str
    conversation_id: str = Field(index=True)
    message_id: str
    group_id: str | None = Field(default=None, index=True)
    group_message_id: str = Field(default_factory=new_id)
    status: str = Field(default="queued", index=True)
    attempts: int = 0
    result_json: str | None = Field(default=None, sa_column=Column(Text))
    error: str | None = None
    available_at: datetime = Field(default_factory=beijing_now, sa_column=Column(BeijingDateTime()))
    created_at: datetime = Field(default_factory=beijing_now, sa_column=Column(BeijingDateTime()))
