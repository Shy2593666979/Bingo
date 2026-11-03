from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from bingo.db.models.groups import MAX_GROUP_AI_MEMBERS
from bingo.schemas.chat import ChatImageInput
from bingo.schemas.maps import LocationInput


class GroupCreate(BaseModel):
    name: str = Field(min_length=1, max_length=20)
    role_ids: list[str] = Field(min_length=2, max_length=MAX_GROUP_AI_MEMBERS)
    description: str = Field(default="", max_length=300)
    cover: Literal["coffee", "night", "garden"] = "coffee"
    allow_ai_to_ai: bool = True
    mentions_enabled: bool = True
    proactive_enabled: bool = True

    @field_validator("name")
    @classmethod
    def trim_name(cls, value):
        if not value.strip():
            raise ValueError("请填写群聊名称")
        return value.strip()


class GroupUpdate(BaseModel):
    read_aloud: bool | None = None
    archived: bool | None = None
    name: str | None = Field(default=None, min_length=1, max_length=20)
    description: str | None = Field(default=None, max_length=300)
    cover: Literal["coffee", "night", "garden"] | None = None
    allow_ai_to_ai: bool | None = None
    mentions_enabled: bool | None = None
    proactive_enabled: bool | None = None
    muted: bool | None = None
    pinned: bool | None = None


class MentionTarget(BaseModel):
    type: Literal["role", "user"]
    id: str = Field(min_length=1, max_length=80)


class GroupSend(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    client_message_id: str = Field(min_length=8, max_length=80, alias="clientMessageId")
    content: str = Field(min_length=1, max_length=4000)
    mentions: list[str] = Field(default_factory=list, max_length=8)
    mention_all: bool = Field(default=False, alias="mentionAll")
    mention_targets: list[MentionTarget] = Field(
        default_factory=list, max_length=9, alias="mentionTargets"
    )
    reply_to_message_id: str | None = Field(default=None, max_length=80, alias="replyToMessageId")
    images: list[ChatImageInput] = Field(default_factory=list, max_length=1)
    location: LocationInput | None = None

    @field_validator("content")
    @classmethod
    def trim_content(cls, value):
        if not value.strip():
            raise ValueError("请填写消息")
        return value.strip()


class MemberAdd(BaseModel):
    role_ids: list[str] = Field(min_length=1, max_length=8)
