import json
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from bingo.db.repositories import DeviceActionRepository
from bingo.tools.base import BaseTool, ToolContext, ToolResult


class DeviceAlarmCreateTool(BaseTool):
    name = "device_alarm_create"
    description = (
        "在用户的 Android 设备上创建闹钟。必须把相对时间转换成带时区的 ISO 8601 "
        "绝对时间。此操作需要用户在设备上明确确认。"
    )
    parameters = {
        "type": "object",
        "properties": {
            "scheduled_at": {
                "type": "string",
                "description": "带时区的 ISO 8601 时间，例如 2026-09-26T07:00:00+08:00",
            },
            "label": {"type": "string", "description": "闹钟标签"},
            "recurrence": {
                "type": "string",
                "enum": ["none", "daily", "weekdays"],
                "description": "重复方式，默认 none",
            },
        },
        "required": ["scheduled_at", "label"],
        "additionalProperties": False,
    }

    async def run(self, context: ToolContext, **arguments: Any) -> ToolResult:
        scheduled_at = datetime.fromisoformat(str(arguments.get("scheduled_at", "")))
        if scheduled_at.tzinfo is None:
            scheduled_at = scheduled_at.replace(tzinfo=ZoneInfo(context.timezone))
        now = datetime.now(ZoneInfo(context.timezone))
        if scheduled_at.astimezone(ZoneInfo(context.timezone)) <= now:
            raise ValueError("闹钟时间必须晚于当前时间")
        label = str(arguments.get("label", "")).strip()
        if not label:
            raise ValueError("label 不能为空")
        recurrence = str(arguments.get("recurrence", "none"))
        if recurrence not in {"none", "daily", "weekdays"}:
            raise ValueError("recurrence 必须是 none、daily 或 weekdays")

        normalized = {
            "scheduled_at": scheduled_at.isoformat(),
            "label": label,
            "recurrence": recurrence,
        }
        action = await DeviceActionRepository(context.session, context.user.id).create(
            self.name, json.dumps(normalized, ensure_ascii=False)
        )
        return ToolResult(
            content=f"已请求用户确认创建闹钟：{scheduled_at.isoformat()}，标签：{label}",
            client_event={
                "type": "approval_required",
                "action_id": action.id,
                "tool": self.name,
                "title": "创建闹钟",
                "description": f"{scheduled_at.strftime('%Y-%m-%d %H:%M')} · {label}",
                "arguments": normalized,
            },
        )
