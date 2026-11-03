from pydantic import BaseModel, Field, field_validator


class ShareCreate(BaseModel):
    role_id: str = Field(min_length=1, max_length=36)
    introduction: str = Field(min_length=1, max_length=300)
    request_id: str = Field(min_length=8, max_length=80)
    images: list[str] = Field(default_factory=list, max_length=3)
    title: str = Field(default="", max_length=60)
    share_tags: list[str] = Field(default_factory=list, max_length=3)

    @field_validator("title")
    @classmethod
    def trim_title(cls, value):
        return value.strip()

    @field_validator("share_tags")
    @classmethod
    def clean_tags(cls, value):
        result = []
        for tag in value:
            tag = tag.strip()
            if not tag or len(tag) > 20:
                raise ValueError("标签须为1到20个字")
            if tag not in result:
                result.append(tag)
        return result

    @field_validator("introduction")
    @classmethod
    def trim_introduction(cls, value):
        value = value.strip()
        if not value:
            raise ValueError("请写一句搭子介绍")
        return value

    @field_validator("images")
    @classmethod
    def check_images(cls, value):
        for item in value:
            if not item.strip():
                raise ValueError("图片数据无效")
            if len(item) > 6_000_000:
                raise ValueError("图片太大，请选小一点的图片")
        return value


class FavoriteUpdate(BaseModel):
    favorite: bool


class LikeUpdate(BaseModel):
    liked: bool


class CommentCreate(BaseModel):
    content: str = Field(min_length=1, max_length=1000)
    request_id: str = Field(min_length=8, max_length=80)

    @field_validator("content")
    @classmethod
    def trim_content(cls, value):
        value = value.strip()
        if not value:
            raise ValueError("请填写评论内容")
        return value


class ReportCreate(BaseModel):
    reason: str = Field(min_length=2, max_length=300)
