from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    Conversation,
    DeviceAction,
    Message,
)


class DeviceActionRepository:
    def __init__(self, session: AsyncSession, user_id: str) -> None:
        self._session = session
        self._user_id = user_id

    async def create(
        self, tool_name: str, arguments_json: str, conversation_id: str | None = None
    ) -> DeviceAction:
        conversation = (
            await self._session.get(Conversation, conversation_id) if conversation_id else None
        )
        if conversation_id and (conversation is None or conversation.user_id != self._user_id):
            raise ValueError("对话不存在")
        action = DeviceAction(
            user_id=self._user_id,
            tool_name=tool_name,
            arguments_json=arguments_json,
            conversation_id=conversation_id,
        )
        self._session.add(action)
        if conversation:
            self._session.add(
                Message(
                    id=action.id,
                    conversation_id=conversation.id,
                    role="user",
                    role_id=conversation.role_id,
                    message_type="device_action",
                    content=self._summary(action),
                )
            )
        await self._session.commit()
        await self._session.refresh(action)
        return action

    async def get(self, action_id: str) -> DeviceAction | None:
        return (
            await self._session.exec(
                select(DeviceAction).where(
                    DeviceAction.id == action_id,
                    DeviceAction.user_id == self._user_id,
                )
            )
        ).first()

    async def set_status(
        self, action: DeviceAction, status: str, result: str | None = None
    ) -> DeviceAction:
        action.status = status
        action.result = result
        message = await self._session.get(Message, action.id)
        if message and message.message_type == "device_action":
            message.content = self._summary(action)
        await self._session.commit()
        await self._session.refresh(action)
        return action

    @staticmethod
    def _summary(action: DeviceAction) -> str:
        states = {
            "pending": "待用户确认，尚未创建",
            "approved": "用户已确认，设备执行结果尚未收到，不能视为已创建",
            "succeeded": "设备已确认创建成功",
            "submitted": "已交给系统时钟，是否创建成功尚未确认，不能声称已创建",
            "rejected": "用户已取消，未创建",
            "failed": "创建失败",
        }
        return (
            f"[闹钟操作记录] 参数：{action.arguments_json}；"
            f"状态：{states.get(action.status, action.status)}；设备反馈：{action.result or '无'}"
        )
