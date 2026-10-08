import json
from datetime import datetime

from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import DeviceAction, User
from bingo.db.repositories import DeviceActionRepository
from bingo.schemas.device_action import DeviceActionCompletion, DeviceActionResponse
from bingo.services.exceptions import ServiceError


def device_action_response(action: DeviceAction) -> DeviceActionResponse:
    arguments = json.loads(action.arguments_json)
    scheduled_at = arguments.get("scheduled_at", "")
    try:
        scheduled_at = datetime.fromisoformat(scheduled_at).strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        pass
    return DeviceActionResponse(
        id=action.id,
        tool=action.tool_name,
        arguments=arguments,
        status=action.status,
        created_at=action.created_at,
        description=f"{scheduled_at} · {arguments.get('label', '')}",
        result=action.result,
    )


async def approve_device_action(
    action_id: str, session: AsyncSession, user: User
) -> DeviceActionResponse:
    repository = DeviceActionRepository(session, user.id)
    action = await repository.get(action_id)
    if action is None:
        raise ServiceError(status_code=404, detail="设备操作不存在")
    if action.status in {"pending", "failed"}:
        return device_action_response(await repository.set_status(action, "approved"))
    if action.status == "approved":
        return device_action_response(action)
    raise ServiceError(status_code=409, detail="设备操作已处理")


async def reject_device_action(action_id: str, session: AsyncSession, user: User) -> None:
    repository = DeviceActionRepository(session, user.id)
    action = await repository.get(action_id)
    if action is None:
        raise ServiceError(status_code=404, detail="设备操作不存在")
    if action.status == "pending":
        await repository.set_status(action, "rejected")
    elif action.status != "rejected":
        raise ServiceError(status_code=409, detail="设备操作已处理")


async def complete_device_action(
    action_id: str, payload: DeviceActionCompletion, session: AsyncSession, user: User
) -> DeviceActionResponse:
    repository = DeviceActionRepository(session, user.id)
    action = await repository.get(action_id)
    if action is None:
        raise ServiceError(status_code=404, detail="设备操作不存在")
    if payload.status == "succeeded" and (payload.result or "").startswith("已提交给系统"):
        payload = payload.model_copy(update={"status": "submitted"})
    if action.status != "approved":
        if action.status == payload.status and action.result == payload.result:
            return device_action_response(action)
        raise ServiceError(status_code=409, detail="设备操作尚未批准")
    return device_action_response(
        await repository.set_status(action, payload.status, payload.result)
    )
