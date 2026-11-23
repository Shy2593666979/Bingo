import json
from contextlib import aclosing

from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from bingo.api.dependencies import CurrentUserDependency, get_service_context
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
        "read_aloud",
    }:
        raise ServiceError(422, "不支持的游戏操作")
    return await request.app.state.party_games.action(identifier, user.id, payload)


@router.post("/games/{identifier}/messages/{message_id}/speech")
async def message_speech(
    identifier: str, message_id: str, request: Request, user: CurrentUserDependency
):
    context = get_service_context(request)
    text, voice = await request.app.state.party_games.speech_source(
        identifier, message_id, user.id
    )
    voice = voice or context.settings.realtime_call.voice

    async def stream():
        async with aclosing(context.chat_speech.message_events(text, voice)) as events:
            async for item in events:
                yield json.dumps(item, ensure_ascii=False) + "\n"

    return StreamingResponse(
        stream(),
        media_type="application/x-ndjson",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
