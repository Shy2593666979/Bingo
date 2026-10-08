from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from bingo.schemas.device_action import DeviceActionResponse
from bingo.schemas.maps import LocationInput


class ChatImageInput(BaseModel):
    mime_type: Literal["image/jpeg", "image/png", "image/webp"]
    data: str = Field(min_length=1, max_length=8_000_000)


class ChatRequest(BaseModel):
    conversation_id: str | None = None
    run_id: str | None = Field(default=None, min_length=1, max_length=80)
    supersedes_run_id: str | None = Field(default=None, min_length=1, max_length=80)
    content: str = Field(default="", max_length=20_000)
    images: list[ChatImageInput] = Field(default_factory=list, max_length=1)
    location: LocationInput | None = None
    read_aloud: bool = False

    @model_validator(mode="after")
    def require_content_or_image(self) -> "ChatRequest":
        if self.location is not None and self.images:
            raise ValueError("位置和图片请分别发送")
        if not self.content.strip() and not self.images and self.location is None:
            raise ValueError("消息内容和图片不能同时为空")
        return self


class ChatResponse(BaseModel):
    conversation_id: str
    message_id: str
    content: str


class MessageResponse(BaseModel):
    id: str
    conversation_id: str
    role: str
    message_type: str = "chat"
    content: str
    location: LocationInput | None = None
    image_id: str | None = None
    image_mime_type: str | None = None
    assistant_role: str | None = None
    run_id: str | None = None
    status: str = "completed"
    call_status: str | None = None
    call_duration_seconds: int | None = None
    created_at: datetime
    device_action: DeviceActionResponse | None = None


class ConversationResponse(BaseModel):
    id: str
    title: str
    created_at: datetime
    role_id: str | None = None


class MemoryCreate(BaseModel):
    content: str = Field(min_length=1, max_length=2_000)


class MemoryResponse(BaseModel):
    id: str
    content: str
    category: str
    scope: str
    role_id: str | None = None
    created_at: datetime
