from sqlalchemy import UniqueConstraint
from sqlmodel import Field, SQLModel

from .base import new_id


class UserSticker(SQLModel, table=True):
    __tablename__ = "user_stickers"
    __table_args__ = (UniqueConstraint("user_id", "digest"),)
    id: str = Field(default_factory=new_id, primary_key=True)
    user_id: str = Field(index=True)
    digest: str
    label: str
    description: str
    mime_type: str
    deleted: bool = False
