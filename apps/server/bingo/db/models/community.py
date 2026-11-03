from datetime import datetime

from sqlalchemy import Column, Text, UniqueConstraint
from sqlmodel import Field, SQLModel

from bingo.db.time import BeijingDateTime, beijing_now

from .base import new_id


class CharacterShare(SQLModel, table=True):
    __tablename__ = "character_shares"
    __table_args__ = (UniqueConstraint("author_id", "request_id"),)

    id: str = Field(default_factory=new_id, primary_key=True)
    author_id: str = Field(index=True)
    source_role_id: str = Field(index=True)
    request_id: str
    author_name: str
    name: str = Field(index=True)
    introduction: str
    snapshot_json: str = Field(sa_column=Column(Text, nullable=False))
    summary_json: str = Field(sa_column=Column(Text, nullable=False))
    avatar_data: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
    has_avatar: bool = False
    images_json: str | None = Field(default=None, sa_column=Column(Text, nullable=True))
    has_images: bool = False
    parent_share_id: str | None = None
    status: str = Field(default="published", index=True)
    created_at: datetime = Field(
        default_factory=beijing_now, sa_column=Column(BeijingDateTime(), nullable=False, index=True)
    )


class CharacterInstall(SQLModel, table=True):
    __tablename__ = "character_installs"
    __table_args__ = (UniqueConstraint("user_id", "share_id"),)

    id: str = Field(default_factory=new_id, primary_key=True)
    user_id: str = Field(index=True)
    share_id: str = Field(index=True)
    role_id: str = Field(index=True)
    created_at: datetime = Field(
        default_factory=beijing_now, sa_column=Column(BeijingDateTime(), nullable=False)
    )


class CharacterFavorite(SQLModel, table=True):
    __tablename__ = "character_favorites"
    user_id: str = Field(primary_key=True)
    share_id: str = Field(primary_key=True)


class CharacterLike(SQLModel, table=True):
    __tablename__ = "character_likes"
    user_id: str = Field(primary_key=True)
    share_id: str = Field(primary_key=True)


class CharacterComment(SQLModel, table=True):
    __tablename__ = "character_comments"
    __table_args__ = (UniqueConstraint("user_id", "share_id", "request_id"),)
    id: str = Field(default_factory=new_id, primary_key=True)
    user_id: str = Field(index=True)
    share_id: str = Field(index=True)
    request_id: str
    author_name: str
    content: str = Field(sa_column=Column(Text, nullable=False))
    deleted: bool = Field(default=False, index=True)
    created_at: datetime = Field(
        default_factory=beijing_now, sa_column=Column(BeijingDateTime(), nullable=False, index=True)
    )


class CommunityReport(SQLModel, table=True):
    __tablename__ = "community_reports"
    __table_args__ = (UniqueConstraint("user_id", "share_id"),)
    id: str = Field(default_factory=new_id, primary_key=True)
    user_id: str = Field(index=True)
    share_id: str = Field(index=True)
    reason: str
    status: str = Field(default="pending")
    created_at: datetime = Field(
        default_factory=beijing_now, sa_column=Column(BeijingDateTime(), nullable=False)
    )
