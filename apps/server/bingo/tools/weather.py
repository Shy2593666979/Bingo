import json
from datetime import date
from typing import Any

import httpx

from bingo.tools.base import BaseTool, ToolContext, ToolResult


class WeatherTool(BaseTool):
    name = "weather_get"
    description = "查询指定城市当前天气或某一天的天气预报。"
    parameters = {
        "type": "object",
        "properties": {
            "location": {"type": "string", "description": "城市或地区名称"},
            "date": {
                "type": "string",
                "description": "可选日期，格式 YYYY-MM-DD；不填则返回当前天气和近期预报",
            },
        },
        "required": ["location"],
        "additionalProperties": False,
    }

    async def run(self, context: ToolContext, **arguments: Any) -> ToolResult:
        location = str(arguments.get("location", "")).strip()
        if not location:
            raise ValueError("location 不能为空")
        requested_date = arguments.get("date")
        if requested_date:
            date.fromisoformat(str(requested_date))

        async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
            geocoding = await client.get(
                "https://geocoding-api.open-meteo.com/v1/search",
                params={"name": location, "count": 1, "language": "zh", "format": "json"},
            )
            geocoding.raise_for_status()
            locations = geocoding.json().get("results") or []
            if not locations:
                return ToolResult(content=f"未找到地点：{location}")
            place = locations[0]
            params: dict[str, Any] = {
                "latitude": place["latitude"],
                "longitude": place["longitude"],
                "timezone": context.timezone,
                "current": "temperature_2m,apparent_temperature,weather_code,wind_speed_10m",
                "daily": (
                    "weather_code,temperature_2m_max,temperature_2m_min,"
                    "precipitation_probability_max"
                ),
                "forecast_days": 7,
            }
            if requested_date:
                params["start_date"] = requested_date
                params["end_date"] = requested_date
                params.pop("forecast_days")
            weather = await client.get("https://api.open-meteo.com/v1/forecast", params=params)
            weather.raise_for_status()

        return ToolResult(
            content=json.dumps(
                {
                    "location": place.get("name", location),
                    "region": place.get("admin1"),
                    "country": place.get("country"),
                    "timezone": context.timezone,
                    "weather": weather.json(),
                },
                ensure_ascii=False,
            )
        )
