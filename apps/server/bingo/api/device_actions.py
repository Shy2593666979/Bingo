import json

from fastapi import APIRouter, HTTPException, status

from bingo.api.dependencies import CurrentUserDependency, SessionDependency
from bingo.db.models import DeviceAction
from bingo.db.repositories import DeviceActionRepository
from bingo.schemas.device_action import DeviceActionCompletion, DeviceActionResponse

router = APIRouter(tags=["device-actions"])


def _response(action: DeviceAction) -> DeviceActionResponse:
    return DeviceActionResponse(
        id=action.id,
        tool=action.tool_name,
        arguments=json.loads(action.arguments_json),
        status=action.status,
        created_at=action.created_at,
    )


@router.post("/device-actions/{action_id}/approve", response_model=DeviceActionResponse)
async def approve_device_action(
    action_id: str,
    session: SessionDependency,
    user: CurrentUserDependency,
) -> DeviceActionResponse:
    repository = DeviceActionRepository(session, user.id)
    action = await repository.get(action_id)
    if action is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="设备操作不存在")
    if action.status in {"pending", "failed"}:
        return _response(await repository.set_status(action, "approved"))
    if action.status == "approved":
        return _response(action)
    raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="设备操作已处理")


@router.post("/device-actions/{action_id}/reject", status_code=status.HTTP_204_NO_CONTENT)
async def reject_device_action(
    action_id: str,
    session: SessionDependency,
    user: CurrentUserDependency,
) -> None:
    repository = DeviceActionRepository(session, user.id)
    action = await repository.get(action_id)
    if action is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="设备操作不存在")
    if action.status == "pending":
        await repository.set_status(action, "rejected")


@router.post("/device-actions/{action_id}/complete", response_model=DeviceActionResponse)
async def complete_device_action(
    action_id: str,
    payload: DeviceActionCompletion,
    session: SessionDependency,
    user: CurrentUserDependency,
) -> DeviceActionResponse:
    repository = DeviceActionRepository(session, user.id)
    action = await repository.get(action_id)
    if action is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="设备操作不存在")
    if action.status != "approved":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="设备操作尚未批准")
    return _response(await repository.set_status(action, payload.status, payload.result))
