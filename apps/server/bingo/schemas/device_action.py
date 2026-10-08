from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field


class DeviceActionResponse(BaseModel):
    id: str
    tool: str
    arguments: dict[str, Any]
    status: str
    created_at: datetime
    title: str = "创建闹钟"
    description: str = ""
    result: str | None = None


class DeviceActionCompletion(BaseModel):
    status: Literal["succeeded", "failed", "submitted"]
    result: str | None = Field(default=None, max_length=2_000)
