from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from bingo.api.dependencies import CurrentUserDependency
from bingo.api.response import EnvelopeRoute
from bingo.services.exceptions import ServiceError

router = APIRouter(tags=["party-games"], route_class=EnvelopeRoute)


class GameCreate(BaseModel):
    mode: str
    role_ids: list[str] = Field(min_length=2, max_length=6)
    rounds: int = 5
    identity: str | None = None
    mood: str = Field(default="朋友派对", max_length=30)


class GameAction(BaseModel):
    type: str
    value: str = Field(default="", max_length=2000)
    command_id: str = Field(min_length=1, max_length=100)
    revision: int = Field(ge=0)
    epoch: int = 0
    stage: str = Field(default="", max_length=100)


@router.post("/games", status_code=201)
async def create(payload: GameCreate, request: Request, user: CurrentUserDependency):
    return await request.app.state.party_games.create(user, payload)


@router.get("/games")
async def list_games(request: Request, user: CurrentUserDependency):
    return await request.app.state.party_games.list(user.id)


@router.get("/games/{identifier}")
async def get(identifier: str, request: Request, user: CurrentUserDependency):
    return await request.app.state.party_games.get(identifier, user.id)


@router.post("/games/{identifier}/actions")
async def action(
    identifier: str, payload: GameAction, request: Request, user: CurrentUserDependency
):
    if payload.type not in {
        "say",
        "choice",
        "advance",
        "change_question",
        "pause",
        "resume",
        "end",
    }:
        raise ServiceError(422, "不支持的游戏操作")
    return await request.app.state.party_games.action(identifier, user.id, payload)
