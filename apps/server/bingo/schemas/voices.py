from typing import Literal

from pydantic import BaseModel, Field, field_validator


class VoicePayload(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    description: str = Field(default="", max_length=200)
    gender: Literal["male", "female", "unknown"] = "unknown"

    @field_validator("name")
    @classmethod
    def trim_name(cls, value):
        if not value.strip():
            raise ValueError("请填写音色名称")
        return value.strip()


class AssignVoicePayload(BaseModel):
    voice_id: str = Field(min_length=1, max_length=36)
