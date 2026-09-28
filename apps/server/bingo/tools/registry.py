import json
import logging
import time
from collections.abc import Iterable
from typing import Any

from bingo.services.logging import log_event
from bingo.tools.base import BaseTool, ToolContext, ToolResult

logger = logging.getLogger(__name__)


class ToolRegistry:
    def __init__(self, tools: Iterable[BaseTool] = ()) -> None:
        self._tools: dict[str, BaseTool] = {}
        for tool in tools:
            self.register(tool)

    def register(self, tool: BaseTool) -> None:
        if tool.name in self._tools:
            raise ValueError(f"Duplicate tool name: {tool.name}")
        self._tools[tool.name] = tool

    def definitions(self) -> list[dict[str, Any]]:
        return [tool.definition() for tool in self._tools.values()]

    async def execute(self, name: str, arguments_json: str, context: ToolContext) -> ToolResult:
        started_at = time.perf_counter()
        user_id = context.user.id if context is not None else None
        log_event(logger, logging.INFO, "tool.started", tool=name, user_id=user_id)
        tool = self._tools.get(name)
        if tool is None:
            log_event(
                logger,
                logging.WARNING,
                "tool.failed",
                tool=name,
                user_id=user_id,
                duration_ms=_duration_ms(started_at),
                error_type="ToolNotFound",
            )
            return ToolResult(content=f"工具不存在：{name}")
        try:
            arguments = json.loads(arguments_json or "{}")
            if not isinstance(arguments, dict):
                raise ValueError("工具参数必须是 JSON 对象")
            result = await tool.run(context, **arguments)
        except (TypeError, ValueError, json.JSONDecodeError) as error:
            log_event(
                logger,
                logging.WARNING,
                "tool.failed",
                tool=name,
                user_id=user_id,
                duration_ms=_duration_ms(started_at),
                error_type=type(error).__name__,
            )
            return ToolResult(content=f"工具参数错误：{error}")
        except Exception as error:
            log_event(
                logger,
                logging.ERROR,
                "tool.failed",
                tool=name,
                user_id=user_id,
                duration_ms=_duration_ms(started_at),
                error_type=type(error).__name__,
            )
            return ToolResult(content=f"工具执行失败：{error}")
        log_event(
            logger,
            logging.INFO,
            "tool.completed",
            tool=name,
            user_id=user_id,
            duration_ms=_duration_ms(started_at),
        )
        return result


def _duration_ms(started_at: float) -> int:
    return round((time.perf_counter() - started_at) * 1000)
