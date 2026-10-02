import json

from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import DeviceAction, User
from bingo.db.repositories import DeviceActionRepository
from bingo.schemas.device_action import DeviceActionCompletion, DeviceActionResponse
from bingo.services.exceptions import ServiceError


def _response(action: DeviceAction) -> DeviceActionResponse:
    return DeviceActionResponse(
        id=action.id,
        tool=action.tool_name,
        arguments=json.loads(action.arguments_json),
        status=action.status,
        created_at=action.created_at,
    )


async def approve_device_action(
    action_id: str, session: AsyncSession, user: User
) -> DeviceActionResponse:
    repository = DeviceActionRepository(session, user.id)
    action = await repository.get(action_id)
    if action is None:
        raise ServiceError(status_code=404, detail="设备操作不存在")
    if action.status in {"pending", "failed"}:
        return _response(await repository.set_status(action, "approved"))
    if action.status == "approved":
        return _response(action)
    raise ServiceError(status_code=409, detail="设备操作已处理")


async def reject_device_action(action_id: str, session: AsyncSession, user: User) -> None:
    repository = DeviceActionRepository(session, user.id)
    action = await repository.get(action_id)
    if action is None:
        raise ServiceError(status_code=404, detail="设备操作不存在")
    if action.status == "pending":
        await repository.set_status(action, "rejected")


async def complete_device_action(
    action_id: str, payload: DeviceActionCompletion, session: AsyncSession, user: User
) -> DeviceActionResponse:
    repository = DeviceActionRepository(session, user.id)
    action = await repository.get(action_id)
    if action is None:
        raise ServiceError(status_code=404, detail="设备操作不存在")
    if action.status != "approved":
        raise ServiceError(status_code=409, detail="设备操作尚未批准")
    return _response(await repository.set_status(action, payload.status, payload.result))
