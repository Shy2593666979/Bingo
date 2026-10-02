from typing import Any

from bingo.db.repositories import CallInvitationRepository
from bingo.tools.base import BaseTool, ToolContext, ToolResult


class AssistantCallInviteTool(BaseTool):
    name = "assistant_call_invite"
    description = (
        "向用户发起一次实时语音来电邀请。仅当用户明确要求打电话、想听助手说话，或明显抱怨助手不打电话/不能直接说话时使用。"
        "调用后用户仍需点击接受才能接通；不要声称电话已经接通。不要连续或重复发起来电。"
    )
    parameters = {
        "type": "object",
        "properties": {
            "reason": {
                "type": "string",
                "description": "自然简短的来电原因，不超过80个中文字符",
            },
        },
        "required": ["reason"],
        "additionalProperties": False,
    }

    async def run(self, context: ToolContext, **arguments: Any) -> ToolResult:
        if not context.conversation_id:
            raise ValueError("当前没有可用的会话")
        reason = str(arguments.get("reason", "")).strip()
        if not reason:
            reason = "想和你说说话"
        reason = reason[:200]
        invitation = await CallInvitationRepository(context.session, context.user.id).create(
            conversation_id=context.conversation_id,
            role_id=context.user.role_id,
            caller_name=context.user.role or context.user.assistant_name or "Bingo",
            caller_role=context.user.role,
            reason=reason,
        )
        return ToolResult(
            content="已向用户展示来电邀请，正在等待用户接受或拒绝。不要声称电话已经接通。",
            client_event={
                "type": "incoming_call",
                "call_id": invitation.id,
                "conversation_id": invitation.conversation_id,
                "caller_name": invitation.caller_name,
                "caller_role": invitation.caller_role,
                "reason": invitation.reason,
                "status": invitation.status,
                "expires_at": invitation.expires_at.isoformat(),
            },
        )
