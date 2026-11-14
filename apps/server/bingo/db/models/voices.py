"""Reusable voice assets, independent of companion identity and lifetime."""

from datetime import datetime

from sqlalchemy import Column, Text, UniqueConstraint
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now

from .base import new_id


class Voice(SQLModel, table=True):
    __tablename__ = "voices"
    __table_args__ = (UniqueConstraint("legacy_key", name="uq_voices_legacy_key"),)

    id: str = Field(default_factory=new_id, primary_key=True, max_length=36)
    name: str = Field(max_length=60)
    description: str = Field(default="", sa_column=Column(Text, nullable=False))
    gender: str = Field(default="unknown", max_length=10)
    scope: str = Field(default="private", max_length=12, index=True)
    owner_id: str | None = Field(default=None, max_length=36, index=True)
    provider_voice: str = Field(default="", max_length=255)
    status: str = Field(default="draft", max_length=16, index=True)
    deleted: bool = Field(default=False, index=True)
    legacy_key: str | None = Field(default=None, max_length=255)
    created_at: datetime = Field(default_factory=beijing_now, sa_column=Column(BeijingDateTime()))
    updated_at: datetime = Field(default_factory=beijing_now, sa_column=Column(BeijingDateTime()))
