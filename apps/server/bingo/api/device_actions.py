from fastapi import APIRouter, Response, status

from bingo.api.dependencies import CurrentUserDependency, SessionDependency
from bingo.api.response import EnvelopeRoute
from bingo.schemas.device_action import DeviceActionCompletion, DeviceActionResponse
from bingo.services import device_actions as device_actions_service

router = APIRouter(tags=["device-actions"], route_class=EnvelopeRoute)


@router.post("/device-actions/{action_id}/approve", response_model=DeviceActionResponse)
async def approve_device_action(
    action_id: str, session: SessionDependency, user: CurrentUserDependency
) -> DeviceActionResponse:
    return await device_actions_service.approve_device_action(
        action_id=action_id, session=session, user=user
    )


@router.post("/device-actions/{action_id}/reject", status_code=status.HTTP_204_NO_CONTENT)
async def reject_device_action(
    action_id: str, session: SessionDependency, user: CurrentUserDependency
) -> None:
    await device_actions_service.reject_device_action(
        action_id=action_id, session=session, user=user
    )
    return Response(status_code=204)


@router.post("/device-actions/{action_id}/complete", response_model=DeviceActionResponse)
async def complete_device_action(
    action_id: str,
    payload: DeviceActionCompletion,
    session: SessionDependency,
    user: CurrentUserDependency,
) -> DeviceActionResponse:
    return await device_actions_service.complete_device_action(
        action_id=action_id, payload=payload, session=session, user=user
    )
