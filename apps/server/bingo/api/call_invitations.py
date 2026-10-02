from fastapi import APIRouter, Response, status

from bingo.api.dependencies import CurrentUserDependency, SessionDependency
from bingo.api.response import EnvelopeRoute
from bingo.schemas.call_invitation import CallInvitationResponse
from bingo.services import call_invitations as call_invitations_service

router = APIRouter(prefix="/call-invitations", tags=["call-invitations"], route_class=EnvelopeRoute)


@router.get("/pending", response_model=CallInvitationResponse | None)
async def pending_call_invitation(
    session: SessionDependency, user: CurrentUserDependency
) -> CallInvitationResponse | None:
    return await call_invitations_service.pending_call_invitation(session=session, user=user)


@router.post("/{invitation_id}/accept", response_model=CallInvitationResponse)
async def accept_call_invitation(
    invitation_id: str, session: SessionDependency, user: CurrentUserDependency
) -> CallInvitationResponse:
    return await call_invitations_service.accept_call_invitation(
        invitation_id=invitation_id, session=session, user=user
    )


@router.post("/{invitation_id}/reject", status_code=status.HTTP_204_NO_CONTENT)
async def reject_call_invitation(
    invitation_id: str, session: SessionDependency, user: CurrentUserDependency
) -> Response:
    await call_invitations_service.reject_call_invitation(
        invitation_id=invitation_id, session=session, user=user
    )
    return Response(status_code=204)


@router.post("/{invitation_id}/miss", status_code=status.HTTP_204_NO_CONTENT)
async def miss_call_invitation(
    invitation_id: str, session: SessionDependency, user: CurrentUserDependency
) -> Response:
    await call_invitations_service.miss_call_invitation(
        invitation_id=invitation_id, session=session, user=user
    )
    return Response(status_code=204)
