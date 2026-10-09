from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from bingo.schemas.avatar import validate_avatar

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
    role_id: str | None = None
    birthday: str | None = None
    gender: str | None = None
    user_avatar_data: str | None = None
    avatar_data: str | None = None
    onboarding_complete: bool
    created_at: datetime


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserProfileResponse


class RecoveryProfile(BaseModel):
    birthday: date

    @field_validator("birthday")
    @classmethod
    def valid_birthday(cls, value):
        if not date(1900, 1, 1) <= value <= date.today():
            raise ValueError("请选择有效生日")
        return value


class UserDetailsUpdate(RecoveryProfile):
    username: str = Field(min_length=1, max_length=30)
    gender: Literal["男", "女", "不愿透露"]
    user_avatar_data: str | None = Field(default=None, max_length=3_000_000)

    @field_validator("username")
    @classmethod
    def strip_nickname(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("请输入昵称")
        return value

    @field_validator("user_avatar_data")
    @classmethod
    def check_avatar(cls, value: str | None) -> str | None:
        return validate_avatar(value)


class ResetPassword(RecoveryProfile):
    phone: str = Field(min_length=6, max_length=20, pattern=r"^\+?[0-9]+$")
    username: str = Field(min_length=1, max_length=30)
    new_password: str = Field(min_length=8, max_length=128)


class ChangePassword(BaseModel):
    old_password: str = Field(min_length=8, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


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


class PersonalityUpdate(BaseModel):
    personality: str

    @field_validator("personality")
    @classmethod
    def validate_personality(cls, value: str) -> str:
        return ProfileUpdate.validate_personality(value)


class ProfileOptionsResponse(BaseModel):
    personalities: tuple[str, ...] = PERSONALITIES
    roles: tuple[str, ...]
    role_details: list[dict] = Field(default_factory=list)
