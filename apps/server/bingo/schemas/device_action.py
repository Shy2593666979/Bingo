from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field


class DeviceActionResponse(BaseModel):
    id: str
    tool: str
    arguments: dict[str, Any]
    status: str
    created_at: datetime


class DeviceActionCompletion(BaseModel):
    status: Literal["succeeded", "failed"]
    result: str | None = Field(default=None, max_length=2_000)
