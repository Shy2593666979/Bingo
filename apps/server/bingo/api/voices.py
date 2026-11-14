from typing import Literal

from fastapi import APIRouter, Request, Response

from bingo.api.dependencies import CurrentUserDependency, SessionDependency, get_service_context
from bingo.api.response import EnvelopeRoute
from bingo.schemas.roles import ClonePayload
from bingo.schemas.voices import AssignVoicePayload, VoicePayload
from bingo.services import voices as service

router = APIRouter(tags=["voices"], route_class=EnvelopeRoute)


@router.get("/voices")
async def list_voices(
    user: CurrentUserDependency,
    session: SessionDependency,
    scope: Literal["system", "community", "private"] | None = None,
    gender: Literal["male", "female", "unknown"] | None = None,
):
    return await service.list_voices(user, session, scope, gender)


@router.post("/voices", status_code=201)
async def create_voice(
    payload: VoicePayload, user: CurrentUserDependency, session: SessionDependency
):
    return await service.create_voice(payload, user, session)


@router.put("/voices/{identifier}")
async def update_voice(
    identifier: str,
    payload: VoicePayload,
    user: CurrentUserDependency,
    session: SessionDependency,
):
    return await service.update_voice(identifier, payload, user, session)


@router.delete("/voices/{identifier}", status_code=204)
async def delete_voice(
    identifier: str,
    user: CurrentUserDependency,
    session: SessionDependency,
    request: Request,
):
    await service.delete_voice(identifier, user, session, get_service_context(request))
    return Response(status_code=204)


@router.post("/voices/{identifier}/clone", status_code=202)
async def clone_voice(
    identifier: str,
    payload: ClonePayload,
    user: CurrentUserDependency,
    session: SessionDependency,
    request: Request,
):
    return await service.clone_voice(
        identifier, payload, user, session, get_service_context(request)
    )


@router.post("/voices/{identifier}/preview")
async def preview_voice(
    identifier: str,
    user: CurrentUserDependency,
    session: SessionDependency,
    request: Request,
):
    return await service.preview_voice(identifier, user, session, get_service_context(request))


@router.put("/roles/{identifier}/voice")
async def assign_voice(
    identifier: str,
    payload: AssignVoicePayload,
    user: CurrentUserDependency,
    session: SessionDependency,
):
    return await service.assign_voice(identifier, payload.voice_id, user, session)
