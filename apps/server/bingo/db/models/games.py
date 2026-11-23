"""Private authoritative game state; never serialize this row into an API response."""

from sqlalchemy import Column, Text
from sqlmodel import Field, SQLModel

from bingo.db.time import beijing_now

from .base import new_id


class PartyGame(SQLModel, table=True):
    __tablename__ = "party_games"
    id: str = Field(default_factory=new_id, primary_key=True)
    user_id: str = Field(index=True)
    active_user_id: str | None = Field(default=None, unique=True)
    revision: int = 0
    created_at: str = Field(default_factory=lambda: beijing_now().isoformat(), index=True)
    state_json: str = Field(sa_column=Column(Text, nullable=False))
