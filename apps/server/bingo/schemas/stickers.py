from pydantic import BaseModel, Field


class StickerUpload(BaseModel):
    label: str = Field(min_length=1, max_length=30)
    description: str = Field(default="", max_length=300)
    mime_type: str
    data: str = Field(min_length=1, max_length=7_000_000)
