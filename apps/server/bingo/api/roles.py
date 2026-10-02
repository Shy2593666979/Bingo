from fastapi import APIRouter, Request, Response

from bingo.api.dependencies import CurrentUserDependency, SessionDependency, get_service_context
from bingo.api.response import EnvelopeRoute
from bingo.schemas.chat import ConversationResponse
from bingo.schemas.roles import ClonePayload, RolePayload
from bingo.services import roles as roles_service

router = APIRouter(tags=["roles"], route_class=EnvelopeRoute)


@router.get("/roles")
async def list_roles(user: CurrentUserDependency, session: SessionDependency) -> list[dict]:
    return await roles_service.list_roles(user=user, session=session)


@router.post("/roles/{identifier}/conversation", response_model=ConversationResponse)
async def open_role_conversation(
    identifier: str, user: CurrentUserDependency, session: SessionDependency
) -> ConversationResponse:
    return await roles_service.open_role_conversation(
        identifier=identifier, user=user, session=session
    )


@router.post("/roles", status_code=201)
async def create_role(
    payload: RolePayload, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await roles_service.create_role(payload=payload, user=user, session=session)


@router.put("/roles/{identifier}")
async def update_role(
    identifier: str, payload: RolePayload, user: CurrentUserDependency, session: SessionDependency
) -> dict:
    return await roles_service.update_role(
        identifier=identifier, payload=payload, user=user, session=session
    )


@router.delete("/roles/{identifier}", status_code=204)
async def delete_role(
    identifier: str, user: CurrentUserDependency, session: SessionDependency, request: Request
) -> Response:
    await roles_service.delete_role(
        identifier=identifier, user=user, session=session, context=get_service_context(request)
    )
    return Response(status_code=204)


@router.post("/roles/{identifier}/voice-clone", status_code=202)
async def clone_voice(
    identifier: str,
    payload: ClonePayload,
    user: CurrentUserDependency,
    session: SessionDependency,
    request: Request,
) -> dict:
    return await roles_service.clone_voice(
        identifier=identifier,
        payload=payload,
        user=user,
        session=session,
        context=get_service_context(request),
    )


@router.get("/voice-jobs/{identifier}")
async def voice_job(
    identifier: str, user: CurrentUserDependency, session: SessionDependency, request: Request
) -> dict:
    return await roles_service.voice_job(
        identifier=identifier, user=user, session=session, context=get_service_context(request)
    )


@router.get("/role-voice-samples/{token}")
async def voice_sample(token: str, session: SessionDependency) -> Response:
    asset = await roles_service.voice_sample(token=token, session=session)
    return Response(asset.data, media_type=asset.media_type, headers=asset.headers)


@router.post("/roles/{identifier}/voice-preview")
async def preview_voice(
    identifier: str, user: CurrentUserDependency, session: SessionDependency, request: Request
) -> dict:
    return await roles_service.preview_voice(
        identifier=identifier, user=user, session=session, context=get_service_context(request)
    )
