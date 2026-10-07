from typing import Literal

from pydantic import BaseModel, Field


class MomentRequest(BaseModel):
    conversation_id: str = Field(min_length=1, max_length=36)
    run_id: str = Field(min_length=1, max_length=80)
    mode: Literal["story", "comfort"] = "story"
    previous: str = Field(default="", max_length=16_000)
    seconds: int = Field(default=300, ge=20, le=300)
    characters_per_second: float = Field(default=3.7, ge=2, le=6)
    closing: bool = False


class MomentFinishRequest(BaseModel):
    conversation_id: str = Field(min_length=1, max_length=36)
    session_id: str = Field(min_length=1, max_length=80)
    feature: Literal["一起专注", "小约定", "陪我入睡", "今日小记"]
    summary: str = Field(min_length=1, max_length=300)
