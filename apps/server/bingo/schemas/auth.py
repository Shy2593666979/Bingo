from datetime import datetime

from pydantic import BaseModel, Field, field_validator

PERSONALITIES = ("温柔体贴", "理性严谨", "幽默风趣", "尖酸刻薄", "积极活泼", "沉稳克制")


class Credentials(BaseModel):
    phone: str = Field(min_length=6, max_length=20, pattern=r"^\+?[0-9]+$")
    password: str = Field(min_length=8, max_length=128)

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, value: str) -> str:
        return value.strip()


class UserProfileResponse(BaseModel):
    id: str
    phone: str
    username: str | None
    assistant_name: str | None
    personality: str | None
    role: str | None
    onboarding_complete: bool
    created_at: datetime


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserProfileResponse


class ProfileUpdate(BaseModel):
    username: str = Field(min_length=1, max_length=30)
    assistant_name: str = Field(min_length=1, max_length=30)
    personality: str
    role: str

    @field_validator("username", "assistant_name")
    @classmethod
    def strip_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("名称不能为空")
        return value

    @field_validator("personality")
    @classmethod
    def validate_personality(cls, value: str) -> str:
        if value not in PERSONALITIES:
            raise ValueError("无效的助手性格")
        return value


class ProfileOptionsResponse(BaseModel):
    personalities: tuple[str, ...] = PERSONALITIES
    roles: tuple[str, ...]
