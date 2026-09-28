from bingo.tools.assistant_call import AssistantCallInviteTool
from bingo.tools.device_alarm import DeviceAlarmCreateTool
from bingo.tools.registry import ToolRegistry
from bingo.tools.weather import WeatherTool
from bingo.tools.web_search import WebSearchTool


def create_tool_registry() -> ToolRegistry:
    return ToolRegistry(
        [
            WebSearchTool(),
            WeatherTool(),
            AssistantCallInviteTool(),
            DeviceAlarmCreateTool(),
        ]
    )


__all__ = ["ToolRegistry", "create_tool_registry"]
