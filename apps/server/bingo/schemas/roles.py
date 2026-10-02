from pydantic import BaseModel, Field, field_validator

from bingo.roles.traits import CATEGORIES, TRAITS
from bingo.schemas.auth import PERSONALITIES
from bingo.schemas.avatar import validate_avatar


class RolePayload(BaseModel):
    name: str = Field(min_length=1, max_length=30)
    prompt: str = Field(min_length=1, max_length=2000)
    avatar_data: str | None = Field(default=None, max_length=3000000)
    voice_source_id: str | None = Field(default=None, max_length=36)
    draft: bool = False
    categories: list[str] | None = Field(default=None, min_length=2, max_length=3)
    traits: list[str] | None = Field(default=None, min_length=2, max_length=3)
    role_type: str | None = Field(default=None, max_length=30)
    personality: str | None = Field(default=None, max_length=30)

    @field_validator("role_type")
    @classmethod
    def trim_role_type(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None

    @field_validator("personality")
    @classmethod
    def validate_personality(cls, value: str | None) -> str | None:
        if value is not None and value not in PERSONALITIES:
            raise ValueError("请选择有效的伙伴性格")
        return value

    @field_validator("categories", "traits")
    @classmethod
    def validate_labels(cls, value, info):
        if value is not None:
            allowed = CATEGORIES if info.field_name == "categories" else TRAITS
            if len(set(value)) != len(value) or any(item not in allowed for item in value):
                raise ValueError("请选择有效且不重复的分类和特征")
        return value

    @field_validator("name", "prompt")
    @classmethod
    def trim_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("请输入角色名称和设定")
        return value

    @field_validator("avatar_data")
    @classmethod
    def check_avatar(cls, value: str | None) -> str | None:
        return validate_avatar(value)


class ClonePayload(BaseModel):
    audio: str = Field(min_length=1, max_length=2560000)
    consent: bool
