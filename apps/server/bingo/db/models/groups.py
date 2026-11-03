from datetime import datetime

from sqlalchemy import Column, Text, UniqueConstraint
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now

from .base import new_id

MAX_GROUP_AI_MEMBERS = 8


class ChatGroup(SQLModel, table=True):
    __tablename__ = "chat_groups"
    id: str = Field(default_factory=new_id, primary_key=True)
    owner_id: str = Field(index=True)
    name: str
    description: str = ""
    cover: str = "coffee"
    allow_ai_to_ai: bool = True
    mentions_enabled: bool = True
    proactive_enabled: bool = True
    muted: bool = False
    read_aloud: bool = True
    pinned: bool = False
    archived: bool = False
    active_run_version: int = 0
    next_message_seq: int = 0
    last_read_seq: int = 0
    last_activity_at: datetime = Field(
        default_factory=beijing_now, sa_column=Column(BeijingDateTime(), nullable=False)
    )
    last_proactive_at: datetime | None = Field(
        default=None, sa_column=Column(BeijingDateTime(), nullable=True)
    )
    created_at: datetime = Field(
        default_factory=beijing_now, sa_column=Column(BeijingDateTime(), nullable=False)
    )


class GroupMember(SQLModel, table=True):
    __tablename__ = "chat_group_members"
    group_id: str = Field(primary_key=True)
    role_id: str = Field(primary_key=True)
    name: str
    role_name: str
    avatar_asset: str
    avatar_data: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
    active: bool = True


class GroupCall(SQLModel, table=True):
    __tablename__ = "chat_group_calls"
    id: str = Field(default_factory=new_id, primary_key=True)
    group_id: str = Field(index=True)
    user_id: str = Field(index=True)
    role_ids_json: str = "[]"
    transcript_json: str = Field(default="[]", sa_column=Column(Text, nullable=False))
    status: str = "connecting"
    duration_seconds: int = 0
    created_at: datetime = Field(default_factory=beijing_now, sa_column=Column(BeijingDateTime()))


class GroupMessage(SQLModel, table=True):
    __tablename__ = "chat_group_messages"
    __table_args__ = (UniqueConstraint("group_id", "seq"),)
    id: str = Field(default_factory=new_id, primary_key=True)
    group_id: str = Field(index=True)
    run_id: str = Field(index=True)
    seq: int
    sender_type: str
    sender_role_id: str | None = None
    sender_name: str
    content: str = Field(default="", sa_column=Column(Text, nullable=False))
    attachment_json: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
    mentions_json: str = "[]"
    mention_targets_json: str = "[]"
    mention_all: bool = False
    reply_to_message_id: str | None = Field(default=None, index=True)
    reply_sender_name: str | None = None
    reply_content_preview: str | None = None
    reply_created_at: datetime | None = Field(
        default=None, sa_column=Column(BeijingDateTime(), nullable=True)
    )
    status: str = "completed"
    created_at: datetime = Field(
        default_factory=beijing_now, sa_column=Column(BeijingDateTime(), nullable=False)
    )


class GroupRun(SQLModel, table=True):
    __tablename__ = "chat_group_runs"
    __table_args__ = (UniqueConstraint("group_id", "client_message_id"),)
    id: str = Field(default_factory=new_id, primary_key=True)
    group_id: str = Field(index=True)
    client_message_id: str
    request_json: str
    version: int
    next_event_seq: int = 0
    runtime_mode: str = "legacy_dispatcher"
    force_targets_json: str = "[]"
    max_ai_messages: int = 10
    emitted_ai_messages: int = 0
    generation_calls: int = 0
    decision_calls: int = 0
    status: str = "pending"
    error: str | None = None
    created_at: datetime = Field(
        default_factory=beijing_now, sa_column=Column(BeijingDateTime(), nullable=False)
    )


class GroupRunEvent(SQLModel, table=True):
    __tablename__ = "chat_group_run_events"
    run_id: str = Field(primary_key=True)
    event_seq: int = Field(primary_key=True)
    event_json: str = Field(sa_column=Column(Text, nullable=False))


class GroupMemory(SQLModel, table=True):
    __tablename__ = "chat_group_memories"
    __table_args__ = (UniqueConstraint("group_id", "content"),)
    id: str = Field(default_factory=new_id, primary_key=True)
    group_id: str = Field(index=True)
    content: str
    source_message_id: str
